// SPDX-License-Identifier: BUSL-1.1
// OpenZeppelin Contracts (last updated v4.8.0) (governance/Governor.sol)

pragma solidity ^0.8.0;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import "./IVetoGovernor.sol";

/**
 * @dev Modified lightly from OpenZeppelin's Governor contract to support vetoing.
 */
abstract contract VetoGovernor is Context, ERC165, EIP712, IVetoGovernor, IERC721Receiver, IERC1155Receiver {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");

    // solhint-disable var-name-mixedcase
    struct ProposalCore {
        // --- start retyped from Timers.BlockNumber at offset 0x00 ---
        uint64 voteStart;
        address proposer;
        bytes4 __gap_unused0;
        // --- start retyped from Timers.BlockNumber at offset 0x20 ---
        uint64 voteEnd;
        bytes24 __gap_unused1;
        // --- Remaining fields starting at offset 0x40 ---------------
        bool executed;
        bool canceled;
        bool vetoed;
    }
    // solhint-enable var-name-mixedcase

    string private _name;

    /// @custom:oz-retyped-from mapping(uint256 => Governor.ProposalCore)
    mapping(uint256 => ProposalCore) private _proposals;

    // This queue keeps track of the governor operating on itself. Calls to functions protected by the
    // {onlyGovernance} modifier needs to be whitelisted in this queue. Whitelisting is set in {_beforeExecute},
    // consumed by the {onlyGovernance} modifier and eventually reset in {_afterExecute}. This ensures that the
    // execution of {onlyGovernance} protected calls can only be achieved through successful proposals.
    DoubleEndedQueue.Bytes32Deque private _governanceCall;

    /**
     * @dev Restricts a function so it can only be executed through governance proposals. For example, governance
     * parameter setters in {GovernorSettings} are protected using this modifier.
     *
     * The governance executing address may be different from the Governor's own address, for example it could be a
     * timelock. This can be customized by modules by overriding {_executor}. The executor is only able to invoke these
     * functions during the execution of the governor's {execute} function, and not under any other circumstances. Thus,
     * for example, additional timelock proposers are not able to change governance parameters without going through the
     * governance protocol (since v4.6).
     */
    modifier onlyGovernance() {
        require(_msgSender() == _executor(), "Governor: onlyGovernance");
        if (_executor() != address(this)) {
            bytes32 msgDataHash = keccak256(_msgData());
            // loop until popping the expected operation - throw if deque is empty (operation not authorized)
            while (_governanceCall.popFront() != msgDataHash) {}
        }
        _;
    }

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(string memory name_) EIP712(name_, version()) {
        _name = name_;
    }

    /**
     * @dev Function to receive ETH that will be handled by the governor (disabled if executor is a third party contract)
     */
    receive() external payable virtual {
        require(_executor() == address(this));
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        // In addition to the current interfaceId, also support previous version of the interfaceId that did not
        // include the castVoteWithReasonAndParams() function as standard
        return
            interfaceId ==
            (type(IVetoGovernor).interfaceId ^
                type(IERC6372).interfaceId ^
                this.cancel.selector ^
                this.castVoteWithReasonAndParams.selector ^
                this.castVoteWithReasonAndParamsBySig.selector ^
                this.getVotesWithParams.selector) ||
            // Previous interface for backwards compatibility
            interfaceId == (type(IVetoGovernor).interfaceId ^ type(IERC6372).interfaceId ^ this.cancel.selector) ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IVetoGovernor-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IVetoGovernor-version}.
     */
    function version() public view virtual override returns (string memory) {
        return "1";
    }

    /**
     * @dev See {IVetoGovernor-hashProposal}.
     *
     * The proposal id is produced by hashing the ABI encoded `targets` array, the `values` array, the `calldatas` array,
     * the descriptionHash (bytes32 which itself is the keccak256 hash of the description string) and the `proposer` address.
     * This proposal id can be produced from the proposal data which is part of the {ProposalCreated} event. It can even
     * be computed in advance, before the proposal is submitted.
     *
     * Note that the chainId and the governor address are not part of the proposal id computation. Consequently, the
     * same proposal (with same operation and same description) will have the same id if submitted on multiple governors
     * across multiple networks. This also means that in order to execute the same operation twice (on the same
     * governor) the proposer will have to change the description in order to avoid proposal id conflicts.
     */
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash,
        address proposer
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash, proposer)));
    }

    /**
     * @dev See {IVetoGovernor-state}.
     */
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalCore storage proposal = _proposals[proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        if (proposal.vetoed) {
            return ProposalState.Vetoed;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        }

        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Defeated;
        }
    }

    /**
     * @dev Part of the Governor Bravo's interface: _"The number of votes required in order for a voter to become a proposer"_.
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev See {IVetoGovernor-proposalSnapshot}.
     */
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart;
    }

    /**
     * @dev See {IVetoGovernor-proposalDeadline}.
     */
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteEnd;
    }

    /**
     * @dev Address of the proposer
     */
    function _proposalProposer(uint256 proposalId) internal view virtual returns (address) {
        return _proposals[proposalId].proposer;
    }

    /**
     * @dev Amount of votes already cast passes the threshold limit.
     */
    function _quorumReached(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Is the proposal successful or not.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Get the voting weight of `tokenId`, owned by `account` at a specific `timepoint`, for a vote as described by `params`.
     */
    function _getVotes(
        address account,
        uint256 tokenId,
        uint256 timepoint,
        bytes memory params
    ) internal view virtual returns (uint256);

    /**
     * @dev Register a vote for `proposalId` by `tokenId` with a given `support`, voting `weight` and voting `params`.
     *
     * Note: Support is generic and can represent various things depending on the voting system used.
     */
    function _countVote(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual;

    /**
     * @dev Default additional encoded parameters used by castVote methods that don't include them
     *
     * Note: Should be overridden by specific implementations to use an appropriate value, the
     * meaning of the additional params, in the context of that implementation
     */
    function _defaultParams() internal view virtual returns (bytes memory) {
        return "";
    }

    /**
     * @dev See {IVetoGovernor-propose}.
     */
    function propose(
        uint256 tokenId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        address proposer = _msgSender();
        uint256 currentTimepoint = clock();

        require(
            getVotes(proposer, tokenId, currentTimepoint - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)), proposer);

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");
        require(_proposals[proposalId].proposer == address(0), "Governor: proposal already exists");

        uint256 snapshot = currentTimepoint + votingDelay();
        uint256 deadline = snapshot + votingPeriod();

        _proposals[proposalId] = ProposalCore({
            voteStart: snapshot.toUint64(),
            proposer: proposer,
            __gap_unused0: 0,
            voteEnd: deadline.toUint64(),
            __gap_unused1: 0,
            executed: false,
            canceled: false,
            vetoed: false
        });

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description
        );

        return proposalId;
    }

    /**
     * @dev See {IVetoGovernor-execute}.
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash,
        address proposer
    ) public payable virtual override returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash, proposer);

        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued,
            "Governor: proposal not successful"
        );
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    /**
     * @dev See {IVetoGovernor-cancel}.
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override returns (uint256) {
        address proposer = _msgSender();
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash, proposer);
        require(state(proposalId) == ProposalState.Pending, "Governor: too late to cancel");
        require(proposer == _proposals[proposalId].proposer, "Governor: only proposer can cancel");
        return _cancel(targets, values, calldatas, descriptionHash, proposer);
    }

    /**
     * @dev Internal execution mechanism. Can be overridden to implement different execution mechanism
     */
    function _execute(
        uint256 /* proposalId */,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual {
        string memory errorMessage = "Governor: call reverted without message";
        uint256 _length = targets.length;
        for (uint256 i = 0; i < _length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            Address.verifyCallResult(success, returndata, errorMessage);
        }
    }

    /**
     * @dev Hook before execution is triggered.
     */
    function _beforeExecute(
        uint256 /* proposalId */,
        address[] memory targets,
        uint256[] memory /* values */,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual {
        if (_executor() != address(this)) {
            uint256 _length = targets.length;
            for (uint256 i = 0; i < _length; ++i) {
                if (targets[i] == address(this)) {
                    _governanceCall.pushBack(keccak256(calldatas[i]));
                }
            }
        }
    }

    /**
     * @dev Hook after execution is triggered.
     */
    function _afterExecute(
        uint256 /* proposalId */,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory /* calldatas */,
        bytes32 /*descriptionHash*/
    ) internal virtual {
        if (_executor() != address(this)) {
            if (!_governanceCall.empty()) {
                _governanceCall.clear();
            }
        }
    }

    /**
     * @dev Internal veto mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * veto to allow distinguishing it from executed and canceled proposals.
     *
     * Emits a {IVetoGovernor-ProposalVetoed} event.
     */
    function _veto(uint256 proposalId) internal returns (uint256) {
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Vetoed &&
                status != ProposalState.Canceled &&
                status != ProposalState.Expired &&
                status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].vetoed = true;

        emit ProposalVetoed(proposalId);

        return proposalId;
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed and canceled proposals.
     *
     * Emits a {IVetoGovernor-ProposalCanceled} event.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash,
        address proposer
    ) internal virtual returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash, proposer);

        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Vetoed &&
                status != ProposalState.Canceled &&
                status != ProposalState.Expired &&
                status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev See {IVetoGovernor-getVotes}.
     */
    function getVotes(
        address account,
        uint256 tokenId,
        uint256 timepoint
    ) public view virtual override returns (uint256) {
        return _getVotes(account, tokenId, timepoint, _defaultParams());
    }

    /**
     * @dev See {IVetoGovernor-getVotesWithParams}.
     */
    function getVotesWithParams(
        address account,
        uint256 tokenId,
        uint256 timepoint,
        bytes memory params
    ) public view virtual override returns (uint256) {
        return _getVotes(account, tokenId, timepoint, params);
    }

    /**
     * @dev See {IVetoGovernor-castVote}.
     */
    function castVote(uint256 proposalId, uint256 tokenId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, tokenId, support, "");
    }

    /**
     * @dev See {IVetoGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        string calldata reason
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, tokenId, support, reason);
    }

    /**
     * @dev See {IVetoGovernor-castVoteWithReasonAndParams}.
     */
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, tokenId, support, reason, params);
    }

    /**
     * @dev See {IVetoGovernor-castVoteBySig}.
     */
    function castVoteBySig(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, tokenId, support, "");
    }

    /**
     * @dev See {IVetoGovernor-castVoteWithReasonAndParamsBySig}.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            v,
            r,
            s
        );

        return _castVote(proposalId, voter, tokenId, support, reason, params);
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IVetoGovernor-getVotes} and call the {_countVote} internal function. Uses the _defaultParams().
     *
     * Emits a {IVetoGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint256 tokenId,
        uint8 support,
        string memory reason
    ) internal virtual returns (uint256) {
        return _castVote(proposalId, account, tokenId, support, reason, _defaultParams());
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IVetoGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IVetoGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint256 tokenId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual returns (uint256) {
        ProposalCore storage proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = _getVotes(account, tokenId, proposal.voteStart, params);
        _countVote(proposalId, tokenId, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, tokenId, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, tokenId, proposalId, support, weight, reason, params);
        }

        return weight;
    }

    /**
     * @dev Relays a transaction or function call to an arbitrary target. In cases where the governance executor
     * is some contract other than the governor itself, like when using a timelock, this function can be invoked
     * in a governance proposal to recover tokens or Ether that was sent to the governor contract by mistake.
     * Note that if the executor is simply the governor itself, use of `relay` is redundant.
     */
    function relay(address target, uint256 value, bytes calldata data) external payable virtual onlyGovernance {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        Address.verifyCallResult(success, returndata, "Governor: relay reverted without message");
    }

    /**
     * @dev Address through which the governor executes action. Will be overloaded by module that execute actions
     * through another contract such as a timelock.
     */
    function _executor() internal view virtual returns (address) {
        return address(this);
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
