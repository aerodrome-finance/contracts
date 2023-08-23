// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IVeArtProxy} from "./interfaces/IVeArtProxy.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IReward} from "./interfaces/IReward.sol";
import {IFactoryRegistry} from "./interfaces/factories/IFactoryRegistry.sol";
import {IManagedRewardsFactory} from "./interfaces/factories/IManagedRewardsFactory.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DelegationLogicLibrary} from "./libraries/DelegationLogicLibrary.sol";
import {BalanceLogicLibrary} from "./libraries/BalanceLogicLibrary.sol";
import {SafeCastLibrary} from "./libraries/SafeCastLibrary.sol";

/// @title Voting Escrow
/// @notice veNFT implementation that escrows ERC-20 tokens in the form of an ERC-721 NFT
/// @notice Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for)
/// @author Modified from Solidly (https://github.com/solidlyexchange/solidly/blob/master/contracts/ve.sol)
/// @author Modified from Curve (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
/// @author velodrome.finance, @figs999, @pegahcarter
/// @dev Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).
contract VotingEscrow is IVotingEscrow, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCastLibrary for uint256;
    using SafeCastLibrary for int128;
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    address public immutable forwarder;
    /// @inheritdoc IVotingEscrow
    address public immutable factoryRegistry;
    /// @inheritdoc IVotingEscrow
    address public immutable token;
    /// @inheritdoc IVotingEscrow
    address public distributor;
    /// @inheritdoc IVotingEscrow
    address public voter;
    /// @inheritdoc IVotingEscrow
    address public team;
    /// @inheritdoc IVotingEscrow
    address public artProxy;
    /// @inheritdoc IVotingEscrow
    address public allowedManager;

    mapping(uint256 => GlobalPoint) internal _pointHistory; // epoch -> unsigned global point

    /// @dev Mapping of interface id to bool about whether or not it's supported
    mapping(bytes4 => bool) internal supportedInterfaces;

    /// @dev ERC165 interface ID of ERC165
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;

    /// @dev ERC165 interface ID of ERC721
    bytes4 internal constant ERC721_INTERFACE_ID = 0x80ac58cd;

    /// @dev ERC165 interface ID of ERC721Metadata
    bytes4 internal constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

    /// @dev ERC165 interface ID of ERC4906
    bytes4 internal constant ERC4906_INTERFACE_ID = 0x49064906;

    /// @dev ERC165 interface ID of ERC6372
    bytes4 internal constant ERC6372_INTERFACE_ID = 0xda287a1d;

    /// @inheritdoc IVotingEscrow
    uint256 public tokenId;

    /// @param _forwarder address of trusted forwarder
    /// @param _token `AERO` token address
    /// @param _factoryRegistry Factory Registry address
    constructor(address _forwarder, address _token, address _factoryRegistry) ERC2771Context(_forwarder) {
        forwarder = _forwarder;
        token = _token;
        factoryRegistry = _factoryRegistry;
        team = _msgSender();
        voter = _msgSender();

        _pointHistory[0].blk = block.number;
        _pointHistory[0].ts = block.timestamp;

        supportedInterfaces[ERC165_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_METADATA_INTERFACE_ID] = true;
        supportedInterfaces[ERC4906_INTERFACE_ID] = true;
        supportedInterfaces[ERC6372_INTERFACE_ID] = true;

        // mint-ish
        emit Transfer(address(0), address(this), tokenId);
        // burn-ish
        emit Transfer(address(this), address(0), tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => EscrowType) public escrowType;

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => uint256) public idToManaged;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => mapping(uint256 => uint256)) public weights;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => bool) public deactivated;

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => address) public managedToLocked;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => address) public managedToFree;

    /*///////////////////////////////////////////////////////////////
                            MANAGED NFT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function createManagedLockFor(address _to) external nonReentrant returns (uint256 _mTokenId) {
        address sender = _msgSender();
        if (sender != allowedManager && sender != IVoter(voter).governor()) revert NotGovernorOrManager();

        _mTokenId = ++tokenId;
        _mint(_to, _mTokenId);
        _depositFor(_mTokenId, 0, 0, LockedBalance(0, 0, true), DepositType.CREATE_LOCK_TYPE);

        escrowType[_mTokenId] = EscrowType.MANAGED;

        (address _lockedManagedReward, address _freeManagedReward) = IManagedRewardsFactory(
            IFactoryRegistry(factoryRegistry).managedRewardsFactory()
        ).createRewards(forwarder, voter);
        managedToLocked[_mTokenId] = _lockedManagedReward;
        managedToFree[_mTokenId] = _freeManagedReward;

        emit CreateManaged(_to, _mTokenId, sender, _lockedManagedReward, _freeManagedReward);
    }

    /// @inheritdoc IVotingEscrow
    function depositManaged(uint256 _tokenId, uint256 _mTokenId) external nonReentrant {
        if (_msgSender() != voter) revert NotVoter();
        if (escrowType[_mTokenId] != EscrowType.MANAGED) revert NotManagedNFT();
        if (escrowType[_tokenId] != EscrowType.NORMAL) revert NotNormalNFT();
        if (_balanceOfNFTAt(_tokenId, block.timestamp) == 0) revert ZeroBalance();

        // adjust user nft
        int128 _amount = _locked[_tokenId].amount;
        if (_locked[_tokenId].isPermanent) {
            permanentLockBalance -= _amount.toUint256();
            _delegate(_tokenId, 0);
        }
        _checkpoint(_tokenId, _locked[_tokenId], LockedBalance(0, 0, false));
        _locked[_tokenId] = LockedBalance(0, 0, false);

        // adjust managed nft
        uint256 _weight = _amount.toUint256();
        permanentLockBalance += _weight;
        LockedBalance memory newLocked = _locked[_mTokenId];
        newLocked.amount += _amount;
        _checkpointDelegatee(_delegates[_mTokenId], _weight, true);
        _checkpoint(_mTokenId, _locked[_mTokenId], newLocked);
        _locked[_mTokenId] = newLocked;

        weights[_tokenId][_mTokenId] = _weight;
        idToManaged[_tokenId] = _mTokenId;
        escrowType[_tokenId] = EscrowType.LOCKED;

        address _lockedManagedReward = managedToLocked[_mTokenId];
        IReward(_lockedManagedReward)._deposit(_weight, _tokenId);
        address _freeManagedReward = managedToFree[_mTokenId];
        IReward(_freeManagedReward)._deposit(_weight, _tokenId);

        emit DepositManaged(_ownerOf(_tokenId), _tokenId, _mTokenId, _weight, block.timestamp);
        emit MetadataUpdate(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function withdrawManaged(uint256 _tokenId) external nonReentrant {
        uint256 _mTokenId = idToManaged[_tokenId];
        if (_msgSender() != voter) revert NotVoter();
        if (_mTokenId == 0) revert InvalidManagedNFTId();
        if (escrowType[_tokenId] != EscrowType.LOCKED) revert NotLockedNFT();

        // update accrued rewards
        address _lockedManagedReward = managedToLocked[_mTokenId];
        address _freeManagedReward = managedToFree[_mTokenId];
        uint256 _weight = weights[_tokenId][_mTokenId];
        uint256 _reward = IReward(_lockedManagedReward).earned(address(token), _tokenId);
        uint256 _total = _weight + _reward;
        uint256 _unlockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;

        // claim locked rewards (rebases + compounded reward)
        address[] memory rewards = new address[](1);
        rewards[0] = address(token);
        IReward(_lockedManagedReward).getReward(_tokenId, rewards);

        // adjust user nft
        LockedBalance memory newLockedNormal = LockedBalance(_total.toInt128(), _unlockTime, false);
        _checkpoint(_tokenId, _locked[_tokenId], newLockedNormal);
        _locked[_tokenId] = newLockedNormal;

        // adjust managed nft
        LockedBalance memory newLockedManaged = _locked[_mTokenId];
        // do not expect _total > locked.amount / permanentLockBalance but just in case
        newLockedManaged.amount -= (
            _total.toInt128() < newLockedManaged.amount ? _total.toInt128() : newLockedManaged.amount
        );
        permanentLockBalance -= (_total < permanentLockBalance ? _total : permanentLockBalance);
        _checkpointDelegatee(_delegates[_mTokenId], _total, false);
        _checkpoint(_mTokenId, _locked[_mTokenId], newLockedManaged);
        _locked[_mTokenId] = newLockedManaged;

        IReward(_lockedManagedReward)._withdraw(_weight, _tokenId);
        IReward(_freeManagedReward)._withdraw(_weight, _tokenId);

        delete idToManaged[_tokenId];
        delete weights[_tokenId][_mTokenId];
        delete escrowType[_tokenId];

        emit WithdrawManaged(_ownerOf(_tokenId), _tokenId, _mTokenId, _total, block.timestamp);
        emit MetadataUpdate(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function setAllowedManager(address _allowedManager) external {
        if (_msgSender() != IVoter(voter).governor()) revert NotGovernor();
        if (_allowedManager == allowedManager) revert SameAddress();
        if (_allowedManager == address(0)) revert ZeroAddress();
        allowedManager = _allowedManager;
        emit SetAllowedManager(_allowedManager);
    }

    /// @inheritdoc IVotingEscrow
    function setManagedState(uint256 _mTokenId, bool _state) external {
        if (_msgSender() != IVoter(voter).emergencyCouncil() && _msgSender() != IVoter(voter).governor())
            revert NotEmergencyCouncilOrGovernor();
        if (escrowType[_mTokenId] != EscrowType.MANAGED) revert NotManagedNFT();
        if (deactivated[_mTokenId] == _state) revert SameState();
        deactivated[_mTokenId] = _state;
    }

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public constant name = "veNFT";
    string public constant symbol = "veNFT";
    string public constant version = "2.0.0";
    uint8 public constant decimals = 18;

    function setTeam(address _team) external {
        if (_msgSender() != team) revert NotTeam();
        if (_team == address(0)) revert ZeroAddress();
        team = _team;
    }

    function setArtProxy(address _proxy) external {
        if (_msgSender() != team) revert NotTeam();
        artProxy = _proxy;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /// @inheritdoc IVotingEscrow
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        if (_ownerOf(_tokenId) == address(0)) revert NonExistentToken();
        return IVeArtProxy(artProxy).tokenURI(_tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from NFT ID to the address that owns it.
    mapping(uint256 => address) internal idToOwner;

    /// @dev Mapping from owner address to count of his tokens.
    mapping(address => uint256) internal ownerToNFTokenCount;

    function _ownerOf(uint256 _tokenId) internal view returns (address) {
        return idToOwner[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function ownerOf(uint256 _tokenId) external view returns (address) {
        return _ownerOf(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function balanceOf(address _owner) external view returns (uint256) {
        return ownerToNFTokenCount[_owner];
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from NFT ID to approved address.
    mapping(uint256 => address) internal idToApprovals;

    /// @dev Mapping from owner address to mapping of operator addresses.
    mapping(address => mapping(address => bool)) internal ownerToOperators;

    mapping(uint256 => uint256) internal ownershipChange;

    /// @inheritdoc IVotingEscrow
    function getApproved(uint256 _tokenId) external view returns (address) {
        return idToApprovals[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return (ownerToOperators[_owner])[_operator];
    }

    /// @inheritdoc IVotingEscrow
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    function _isApprovedOrOwner(address _spender, uint256 _tokenId) internal view returns (bool) {
        address owner = _ownerOf(_tokenId);
        bool spenderIsOwner = owner == _spender;
        bool spenderIsApproved = _spender == idToApprovals[_tokenId];
        bool spenderIsApprovedForAll = (ownerToOperators[owner])[_spender];
        return spenderIsOwner || spenderIsApproved || spenderIsApprovedForAll;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function approve(address _approved, uint256 _tokenId) external {
        address sender = _msgSender();
        address owner = _ownerOf(_tokenId);
        // Throws if `_tokenId` is not a valid NFT
        if (owner == address(0)) revert ZeroAddress();
        // Throws if `_approved` is the current owner
        if (owner == _approved) revert SameAddress();
        // Check requirements
        bool senderIsOwner = (_ownerOf(_tokenId) == sender);
        bool senderIsApprovedForAll = (ownerToOperators[owner])[sender];
        if (!senderIsOwner && !senderIsApprovedForAll) revert NotApprovedOrOwner();
        // Set the approval
        idToApprovals[_tokenId] = _approved;
        emit Approval(owner, _approved, _tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function setApprovalForAll(address _operator, bool _approved) external {
        address sender = _msgSender();
        // Throws if `_operator` is the `msg.sender`
        if (_operator == sender) revert SameAddress();
        ownerToOperators[sender][_operator] = _approved;
        emit ApprovalForAll(sender, _operator, _approved);
    }

    /* TRANSFER FUNCTIONS */

    function _transferFrom(address _from, address _to, uint256 _tokenId, address _sender) internal {
        if (escrowType[_tokenId] == EscrowType.LOCKED) revert NotManagedOrNormalNFT();
        // Check requirements
        if (!_isApprovedOrOwner(_sender, _tokenId)) revert NotApprovedOrOwner();
        // Clear approval. Throws if `_from` is not the current owner
        if (_ownerOf(_tokenId) != _from) revert NotOwner();
        delete idToApprovals[_tokenId];
        // Remove NFT. Throws if `_tokenId` is not a valid NFT
        _removeTokenFrom(_from, _tokenId);
        // Update voting checkpoints
        _checkpointDelegator(_tokenId, 0, _to);
        // Add NFT
        _addTokenTo(_to, _tokenId);
        // Set the block of ownership transfer (for Flash NFT protection)
        ownershipChange[_tokenId] = block.number;
        // Log the transfer
        emit Transfer(_from, _to, _tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function transferFrom(address _from, address _to, uint256 _tokenId) external {
        _transferFrom(_from, _to, _tokenId, _msgSender());
    }

    /// @inheritdoc IVotingEscrow
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @inheritdoc IVotingEscrow
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) public {
        address sender = _msgSender();
        _transferFrom(_from, _to, _tokenId, sender);

        if (_isContract(_to)) {
            // Throws if transfer destination is a contract which does not implement 'onERC721Received'
            try IERC721Receiver(_to).onERC721Received(sender, _from, _tokenId, _data) returns (bytes4 response) {
                if (response != IERC721Receiver(_to).onERC721Received.selector) {
                    revert ERC721ReceiverRejectedTokens();
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert ERC721TransferToNonERC721ReceiverImplementer();
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        return supportedInterfaces[_interfaceID];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    mapping(address => mapping(uint256 => uint256)) public ownerToNFTokenIdList;

    /// @dev Mapping from NFT ID to index of owner
    mapping(uint256 => uint256) internal tokenToOwnerIndex;

    /// @dev Add a NFT to an index mapping to a given address
    /// @param _to address of the receiver
    /// @param _tokenId uint ID Of the token to be added
    function _addTokenToOwnerList(address _to, uint256 _tokenId) internal {
        uint256 currentCount = ownerToNFTokenCount[_to];

        ownerToNFTokenIdList[_to][currentCount] = _tokenId;
        tokenToOwnerIndex[_tokenId] = currentCount;
    }

    /// @dev Add a NFT to a given address
    ///      Throws if `_tokenId` is owned by someone.
    function _addTokenTo(address _to, uint256 _tokenId) internal {
        // Throws if `_tokenId` is owned by someone
        assert(_ownerOf(_tokenId) == address(0));
        // Change the owner
        idToOwner[_tokenId] = _to;
        // Update owner token index tracking
        _addTokenToOwnerList(_to, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_to] += 1;
    }

    /// @dev Function to mint tokens
    ///      Throws if `_to` is zero address.
    ///      Throws if `_tokenId` is owned by someone.
    /// @param _to The address that will receive the minted tokens.
    /// @param _tokenId The token id to mint.
    /// @return A boolean that indicates if the operation was successful.
    function _mint(address _to, uint256 _tokenId) internal returns (bool) {
        // Throws if `_to` is zero address
        assert(_to != address(0));
        // Add NFT. Throws if `_tokenId` is owned by someone
        _addTokenTo(_to, _tokenId);
        // Update voting checkpoints
        _checkpointDelegator(_tokenId, 0, _to);
        emit Transfer(address(0), _to, _tokenId);
        return true;
    }

    /// @dev Remove a NFT from an index mapping to a given address
    /// @param _from address of the sender
    /// @param _tokenId uint ID Of the token to be removed
    function _removeTokenFromOwnerList(address _from, uint256 _tokenId) internal {
        // Delete
        uint256 currentCount = ownerToNFTokenCount[_from] - 1;
        uint256 currentIndex = tokenToOwnerIndex[_tokenId];

        if (currentCount == currentIndex) {
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][currentCount] = 0;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[_tokenId] = 0;
        } else {
            uint256 lastTokenId = ownerToNFTokenIdList[_from][currentCount];

            // Add
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][currentIndex] = lastTokenId;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[lastTokenId] = currentIndex;

            // Delete
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][currentCount] = 0;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[_tokenId] = 0;
        }
    }

    /// @dev Remove a NFT from a given address
    ///      Throws if `_from` is not the current owner.
    function _removeTokenFrom(address _from, uint256 _tokenId) internal {
        // Throws if `_from` is not the current owner
        assert(_ownerOf(_tokenId) == _from);
        // Change the owner
        idToOwner[_tokenId] = address(0);
        // Update owner token index tracking
        _removeTokenFromOwnerList(_from, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_from] -= 1;
    }

    /// @dev Must be called prior to updating `LockedBalance`
    function _burn(uint256 _tokenId) internal {
        address sender = _msgSender();
        if (!_isApprovedOrOwner(sender, _tokenId)) revert NotApprovedOrOwner();
        address owner = _ownerOf(_tokenId);

        // Clear approval
        delete idToApprovals[_tokenId];
        // Update voting checkpoints
        _checkpointDelegator(_tokenId, 0, address(0));
        // Remove token
        _removeTokenFrom(owner, _tokenId);
        emit Transfer(owner, address(0), _tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             ESCROW STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    int128 internal constant iMAXTIME = 4 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;

    /// @inheritdoc IVotingEscrow
    uint256 public epoch;
    /// @inheritdoc IVotingEscrow
    uint256 public supply;

    mapping(uint256 => LockedBalance) internal _locked;
    mapping(uint256 => UserPoint[1000000000]) internal _userPointHistory;
    mapping(uint256 => uint256) public userPointEpoch;
    /// @inheritdoc IVotingEscrow
    mapping(uint256 => int128) public slopeChanges;
    /// @inheritdoc IVotingEscrow
    mapping(address => bool) public canSplit;
    /// @inheritdoc IVotingEscrow
    uint256 public permanentLockBalance;

    /// @inheritdoc IVotingEscrow
    function locked(uint256 _tokenId) external view returns (LockedBalance memory) {
        return _locked[_tokenId];
    }

    /// @inheritdoc IVotingEscrow
    function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (UserPoint memory) {
        return _userPointHistory[_tokenId][_loc];
    }

    /// @inheritdoc IVotingEscrow
    function pointHistory(uint256 _loc) external view returns (GlobalPoint memory) {
        return _pointHistory[_loc];
    }

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Record global and per-user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID. No user checkpoint if 0
    /// @param _oldLocked Pevious locked amount / end lock time for the user
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(uint256 _tokenId, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal {
        UserPoint memory uOld;
        UserPoint memory uNew;
        int128 oldDslope = 0;
        int128 newDslope = 0;
        uint256 _epoch = epoch;

        if (_tokenId != 0) {
            uNew.permanent = _newLocked.isPermanent ? _newLocked.amount.toUint256() : 0;
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                uOld.slope = _oldLocked.amount / iMAXTIME;
                uOld.bias = uOld.slope * (_oldLocked.end - block.timestamp).toInt128();
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                uNew.slope = _newLocked.amount / iMAXTIME;
                uNew.bias = uNew.slope * (_newLocked.end - block.timestamp).toInt128();
            }

            // Read values of scheduled changes in the slope
            // _oldLocked.end can be in the past and in the future
            // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            oldDslope = slopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[_newLocked.end];
                }
            }
        }

        GlobalPoint memory lastPoint = GlobalPoint({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number,
            permanentLockBalance: 0
        });
        if (_epoch > 0) {
            lastPoint = _pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        GlobalPoint memory initialLastPoint = GlobalPoint({
            bias: lastPoint.bias,
            slope: lastPoint.slope,
            ts: lastPoint.ts,
            blk: lastPoint.blk,
            permanentLockBalance: lastPoint.permanentLockBalance
        });
        uint256 blockSlope = 0; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            blockSlope = (MULTIPLIER * (block.number - lastPoint.blk)) / (block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK; // Initial value of t_i is always larger than the ts of the last point
                int128 d_slope = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slopeChanges[t_i];
                }
                lastPoint.bias -= lastPoint.slope * (t_i - lastCheckpoint).toInt128();
                lastPoint.slope += d_slope;
                if (lastPoint.bias < 0) {
                    // This can happen
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    // This cannot happen - just in case
                    lastPoint.slope = 0;
                }
                lastCheckpoint = t_i;
                lastPoint.ts = t_i;
                lastPoint.blk = initialLastPoint.blk + (blockSlope * (t_i - initialLastPoint.ts)) / MULTIPLIER;
                _epoch += 1;
                if (t_i == block.timestamp) {
                    lastPoint.blk = block.number;
                    break;
                } else {
                    _pointHistory[_epoch] = lastPoint;
                }
            }
        }

        if (_tokenId != 0) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            lastPoint.permanentLockBalance = permanentLockBalance;
        }

        // If timestamp of last global point is the same, overwrite the last global point
        // Else record the new global point into history
        // Exclude epoch 0 (note: _epoch is always >= 1, see above)
        // Two possible outcomes:
        // Missing global checkpoints in prior weeks. In this case, _epoch = epoch + x, where x > 1
        // No missing global checkpoints, but timestamp != block.timestamp. Create new checkpoint.
        // No missing global checkpoints, but timestamp == block.timestamp. Overwrite last checkpoint.
        if (_epoch != 1 && _pointHistory[_epoch - 1].ts == block.timestamp) {
            // _epoch = epoch + 1, so we do not increment epoch
            _pointHistory[_epoch - 1] = lastPoint;
        } else {
            // more than one global point may have been written, so we update epoch
            epoch = _epoch;
            _pointHistory[_epoch] = lastPoint;
        }

        if (_tokenId != 0) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_newLocked.end]
            // and add old_user_slope to [_oldLocked.end]
            if (_oldLocked.end > block.timestamp) {
                // oldDslope was <something> - uOld.slope, so we cancel that
                oldDslope += uOld.slope;
                if (_newLocked.end == _oldLocked.end) {
                    oldDslope -= uNew.slope; // It was a new deposit, not extension
                }
                slopeChanges[_oldLocked.end] = oldDslope;
            }

            if (_newLocked.end > block.timestamp) {
                // update slope if new lock is greater than old lock and is not permanent or if old lock is permanent
                if ((_newLocked.end > _oldLocked.end)) {
                    newDslope -= uNew.slope; // old slope disappeared at this point
                    slopeChanges[_newLocked.end] = newDslope;
                }
                // else: we recorded it already in oldDslope
            }
            // If timestamp of last user point is the same, overwrite the last user point
            // Else record the new user point into history
            // Exclude epoch 0
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            uint256 userEpoch = userPointEpoch[_tokenId];
            if (userEpoch != 0 && _userPointHistory[_tokenId][userEpoch].ts == block.timestamp) {
                _userPointHistory[_tokenId][userEpoch] = uNew;
            } else {
                userPointEpoch[_tokenId] = ++userEpoch;
                _userPointHistory[_tokenId][userEpoch] = uNew;
            }
        }
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param _oldLocked Previous locked amount / timestamp
    /// @param _depositType The type of deposit
    function _depositFor(
        uint256 _tokenId,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance memory _oldLocked,
        DepositType _depositType
    ) internal {
        uint256 supplyBefore = supply;
        supply = supplyBefore + _value;

        // Set newLocked to _oldLocked without mangling memory
        LockedBalance memory newLocked;
        (newLocked.amount, newLocked.end, newLocked.isPermanent) = (
            _oldLocked.amount,
            _oldLocked.end,
            _oldLocked.isPermanent
        );

        // Adding to existing lock, or if a lock is expired - creating a new one
        newLocked.amount += _value.toInt128();
        if (_unlockTime != 0) {
            newLocked.end = _unlockTime;
        }
        _locked[_tokenId] = newLocked;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // or if the lock is a permanent lock, then _oldLocked.end == 0
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // newLocked.end > block.timestamp (always)
        _checkpoint(_tokenId, _oldLocked, newLocked);

        address from = _msgSender();
        if (_value != 0) {
            IERC20(token).safeTransferFrom(from, address(this), _value);
        }

        emit Deposit(from, _tokenId, _depositType, _value, newLocked.end, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }

    /// @inheritdoc IVotingEscrow
    function checkpoint() external nonReentrant {
        _checkpoint(0, LockedBalance(0, 0, false), LockedBalance(0, 0, false));
    }

    /// @inheritdoc IVotingEscrow
    function depositFor(uint256 _tokenId, uint256 _value) external nonReentrant {
        if (escrowType[_tokenId] == EscrowType.MANAGED && _msgSender() != distributor) revert NotDistributor();
        _increaseAmountFor(_tokenId, _value, DepositType.DEPOSIT_FOR_TYPE);
    }

    /// @dev Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    /// @param _to Address to deposit
    function _createLock(uint256 _value, uint256 _lockDuration, address _to) internal returns (uint256) {
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (_value == 0) revert ZeroAmount();
        if (unlockTime <= block.timestamp) revert LockDurationNotInFuture();
        if (unlockTime > block.timestamp + MAXTIME) revert LockDurationTooLong();

        uint256 _tokenId = ++tokenId;
        _mint(_to, _tokenId);

        _depositFor(_tokenId, _value, unlockTime, _locked[_tokenId], DepositType.CREATE_LOCK_TYPE);
        return _tokenId;
    }

    /// @inheritdoc IVotingEscrow
    function createLock(uint256 _value, uint256 _lockDuration) external nonReentrant returns (uint256) {
        return _createLock(_value, _lockDuration, _msgSender());
    }

    /// @inheritdoc IVotingEscrow
    function createLockFor(uint256 _value, uint256 _lockDuration, address _to) external nonReentrant returns (uint256) {
        return _createLock(_value, _lockDuration, _to);
    }

    function _increaseAmountFor(uint256 _tokenId, uint256 _value, DepositType _depositType) internal {
        EscrowType _escrowType = escrowType[_tokenId];
        if (_escrowType == EscrowType.LOCKED) revert NotManagedOrNormalNFT();

        LockedBalance memory oldLocked = _locked[_tokenId];

        if (_value == 0) revert ZeroAmount();
        if (oldLocked.amount <= 0) revert NoLockFound();
        if (oldLocked.end <= block.timestamp && !oldLocked.isPermanent) revert LockExpired();

        if (oldLocked.isPermanent) permanentLockBalance += _value;
        _checkpointDelegatee(_delegates[_tokenId], _value, true);
        _depositFor(_tokenId, _value, 0, oldLocked, _depositType);

        if (_escrowType == EscrowType.MANAGED) {
            // increaseAmount called on managed tokens are treated as locked rewards
            address _lockedManagedReward = managedToLocked[_tokenId];
            address _token = token;
            IERC20(_token).safeApprove(_lockedManagedReward, _value);
            IReward(_lockedManagedReward).notifyRewardAmount(_token, _value);
            IERC20(_token).safeApprove(_lockedManagedReward, 0);
        }

        emit MetadataUpdate(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function increaseAmount(uint256 _tokenId, uint256 _value) external nonReentrant {
        if (!_isApprovedOrOwner(_msgSender(), _tokenId)) revert NotApprovedOrOwner();
        _increaseAmountFor(_tokenId, _value, DepositType.INCREASE_LOCK_AMOUNT);
    }

    /// @inheritdoc IVotingEscrow
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external nonReentrant {
        if (!_isApprovedOrOwner(_msgSender(), _tokenId)) revert NotApprovedOrOwner();
        if (escrowType[_tokenId] != EscrowType.NORMAL) revert NotNormalNFT();

        LockedBalance memory oldLocked = _locked[_tokenId];
        if (oldLocked.isPermanent) revert PermanentLock();
        uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (oldLocked.end <= block.timestamp) revert LockExpired();
        if (oldLocked.amount <= 0) revert NoLockFound();
        if (unlockTime <= oldLocked.end) revert LockDurationNotInFuture();
        if (unlockTime > block.timestamp + MAXTIME) revert LockDurationTooLong();

        _depositFor(_tokenId, 0, unlockTime, oldLocked, DepositType.INCREASE_UNLOCK_TIME);

        emit MetadataUpdate(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function withdraw(uint256 _tokenId) external nonReentrant {
        address sender = _msgSender();
        if (!_isApprovedOrOwner(sender, _tokenId)) revert NotApprovedOrOwner();
        if (voted[_tokenId]) revert AlreadyVoted();
        if (escrowType[_tokenId] != EscrowType.NORMAL) revert NotNormalNFT();

        LockedBalance memory oldLocked = _locked[_tokenId];
        if (oldLocked.isPermanent) revert PermanentLock();
        if (block.timestamp < oldLocked.end) revert LockNotExpired();
        uint256 value = oldLocked.amount.toUint256();

        // Burn the NFT
        _burn(_tokenId);
        _locked[_tokenId] = LockedBalance(0, 0, false);
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // oldLocked can have either expired <= timestamp or zero end
        // oldLocked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(_tokenId, oldLocked, LockedBalance(0, 0, false));

        IERC20(token).safeTransfer(sender, value);

        emit Withdraw(sender, _tokenId, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    /// @inheritdoc IVotingEscrow
    function merge(uint256 _from, uint256 _to) external nonReentrant {
        address sender = _msgSender();
        if (voted[_from]) revert AlreadyVoted();
        if (escrowType[_from] != EscrowType.NORMAL) revert NotNormalNFT();
        if (escrowType[_to] != EscrowType.NORMAL) revert NotNormalNFT();
        if (_from == _to) revert SameNFT();
        if (!_isApprovedOrOwner(sender, _from)) revert NotApprovedOrOwner();
        if (!_isApprovedOrOwner(sender, _to)) revert NotApprovedOrOwner();
        LockedBalance memory oldLockedTo = _locked[_to];
        if (oldLockedTo.end <= block.timestamp && !oldLockedTo.isPermanent) revert LockExpired();

        LockedBalance memory oldLockedFrom = _locked[_from];
        if (oldLockedFrom.isPermanent) revert PermanentLock();
        uint256 end = oldLockedFrom.end >= oldLockedTo.end ? oldLockedFrom.end : oldLockedTo.end;

        _burn(_from);
        _locked[_from] = LockedBalance(0, 0, false);
        _checkpoint(_from, oldLockedFrom, LockedBalance(0, 0, false));

        LockedBalance memory newLockedTo;
        newLockedTo.amount = oldLockedTo.amount + oldLockedFrom.amount;
        newLockedTo.isPermanent = oldLockedTo.isPermanent;
        if (newLockedTo.isPermanent) {
            permanentLockBalance += oldLockedFrom.amount.toUint256();
        } else {
            newLockedTo.end = end;
        }
        _checkpointDelegatee(_delegates[_to], oldLockedFrom.amount.toUint256(), true);
        _checkpoint(_to, oldLockedTo, newLockedTo);
        _locked[_to] = newLockedTo;

        emit Merge(
            sender,
            _from,
            _to,
            oldLockedFrom.amount.toUint256(),
            oldLockedTo.amount.toUint256(),
            newLockedTo.amount.toUint256(),
            newLockedTo.end,
            block.timestamp
        );
        emit MetadataUpdate(_to);
    }

    /// @inheritdoc IVotingEscrow
    function split(
        uint256 _from,
        uint256 _amount
    ) external nonReentrant returns (uint256 _tokenId1, uint256 _tokenId2) {
        address sender = _msgSender();
        address owner = _ownerOf(_from);
        if (owner == address(0)) revert SplitNoOwner();
        if (!canSplit[owner] && !canSplit[address(0)]) revert SplitNotAllowed();
        if (escrowType[_from] != EscrowType.NORMAL) revert NotNormalNFT();
        if (voted[_from]) revert AlreadyVoted();
        if (!_isApprovedOrOwner(sender, _from)) revert NotApprovedOrOwner();
        LockedBalance memory newLocked = _locked[_from];
        if (newLocked.end <= block.timestamp && !newLocked.isPermanent) revert LockExpired();
        int128 _splitAmount = _amount.toInt128();
        if (_splitAmount == 0) revert ZeroAmount();
        if (newLocked.amount <= _splitAmount) revert AmountTooBig();

        // Zero out and burn old veNFT
        _burn(_from);
        _locked[_from] = LockedBalance(0, 0, false);
        _checkpoint(_from, newLocked, LockedBalance(0, 0, false));

        // Create new veNFT using old balance - amount
        newLocked.amount -= _splitAmount;
        _tokenId1 = _createSplitNFT(owner, newLocked);

        // Create new veNFT using amount
        newLocked.amount = _splitAmount;
        _tokenId2 = _createSplitNFT(owner, newLocked);

        emit Split(
            _from,
            _tokenId1,
            _tokenId2,
            sender,
            _locked[_tokenId1].amount.toUint256(),
            _splitAmount.toUint256(),
            newLocked.end,
            block.timestamp
        );
    }

    function _createSplitNFT(address _to, LockedBalance memory _newLocked) private returns (uint256 _tokenId) {
        _tokenId = ++tokenId;
        _locked[_tokenId] = _newLocked;
        _checkpoint(_tokenId, LockedBalance(0, 0, false), _newLocked);
        _mint(_to, _tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function toggleSplit(address _account, bool _bool) external {
        if (_msgSender() != team) revert NotTeam();
        canSplit[_account] = _bool;
    }

    /// @inheritdoc IVotingEscrow
    function lockPermanent(uint256 _tokenId) external {
        address sender = _msgSender();
        if (!_isApprovedOrOwner(sender, _tokenId)) revert NotApprovedOrOwner();
        if (escrowType[_tokenId] != EscrowType.NORMAL) revert NotNormalNFT();
        LockedBalance memory _newLocked = _locked[_tokenId];
        if (_newLocked.isPermanent) revert PermanentLock();
        if (_newLocked.end <= block.timestamp) revert LockExpired();
        if (_newLocked.amount <= 0) revert NoLockFound();

        uint256 _amount = _newLocked.amount.toUint256();
        permanentLockBalance += _amount;
        _newLocked.end = 0;
        _newLocked.isPermanent = true;
        _checkpoint(_tokenId, _locked[_tokenId], _newLocked);
        _locked[_tokenId] = _newLocked;

        emit LockPermanent(sender, _tokenId, _amount, block.timestamp);
        emit MetadataUpdate(_tokenId);
    }

    /// @inheritdoc IVotingEscrow
    function unlockPermanent(uint256 _tokenId) external {
        address sender = _msgSender();
        if (!_isApprovedOrOwner(sender, _tokenId)) revert NotApprovedOrOwner();
        if (escrowType[_tokenId] != EscrowType.NORMAL) revert NotNormalNFT();
        if (voted[_tokenId]) revert AlreadyVoted();
        LockedBalance memory _newLocked = _locked[_tokenId];
        if (!_newLocked.isPermanent) revert NotPermanentLock();

        uint256 _amount = _newLocked.amount.toUint256();
        permanentLockBalance -= _amount;
        _newLocked.end = ((block.timestamp + MAXTIME) / WEEK) * WEEK;
        _newLocked.isPermanent = false;
        _delegate(_tokenId, 0);
        _checkpoint(_tokenId, _locked[_tokenId], _newLocked);
        _locked[_tokenId] = _newLocked;

        emit UnlockPermanent(sender, _tokenId, _amount, block.timestamp);
        emit MetadataUpdate(_tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                           GAUGE VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    function _balanceOfNFTAt(uint256 _tokenId, uint256 _t) internal view returns (uint256) {
        return BalanceLogicLibrary.balanceOfNFTAt(userPointEpoch, _userPointHistory, _tokenId, _t);
    }

    function _supplyAt(uint256 _timestamp) internal view returns (uint256) {
        return BalanceLogicLibrary.supplyAt(slopeChanges, _pointHistory, epoch, _timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function balanceOfNFT(uint256 _tokenId) public view returns (uint256) {
        if (ownershipChange[_tokenId] == block.number) return 0;
        return _balanceOfNFTAt(_tokenId, block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        return _balanceOfNFTAt(_tokenId, _t);
    }

    /// @inheritdoc IVotingEscrow
    function totalSupply() external view returns (uint256) {
        return _supplyAt(block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function totalSupplyAt(uint256 _timestamp) external view returns (uint256) {
        return _supplyAt(_timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                            GAUGE VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => bool) public voted;

    /// @inheritdoc IVotingEscrow
    function setVoterAndDistributor(address _voter, address _distributor) external {
        if (_msgSender() != voter) revert NotVoter();
        voter = _voter;
        distributor = _distributor;
    }

    /// @inheritdoc IVotingEscrow
    function voting(uint256 _tokenId, bool _voted) external {
        if (_msgSender() != voter) revert NotVoter();
        voted[_tokenId] = _voted;
    }

    /*///////////////////////////////////////////////////////////////
                            DAO VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(uint256 delegator,uint256 delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of each accounts delegate
    mapping(uint256 => uint256) private _delegates;

    /// @notice A record of delegated token checkpoints for each tokenId, by index
    mapping(uint256 => mapping(uint48 => Checkpoint)) private _checkpoints;

    /// @inheritdoc IVotingEscrow
    mapping(uint256 => uint48) public numCheckpoints;

    /// @inheritdoc IVotingEscrow
    mapping(address => uint256) public nonces;

    /// @inheritdoc IVotingEscrow
    function delegates(uint256 delegator) external view returns (uint256) {
        return _delegates[delegator];
    }

    /// @inheritdoc IVotingEscrow
    function checkpoints(uint256 _tokenId, uint48 _index) external view returns (Checkpoint memory) {
        return _checkpoints[_tokenId][_index];
    }

    /// @inheritdoc IVotingEscrow
    function getPastVotes(address _account, uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        return DelegationLogicLibrary.getPastVotes(numCheckpoints, _checkpoints, _account, _tokenId, _timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function getPastTotalSupply(uint256 _timestamp) external view returns (uint256) {
        return _supplyAt(_timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                             DAO VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _checkpointDelegator(uint256 _delegator, uint256 _delegatee, address _owner) internal {
        DelegationLogicLibrary.checkpointDelegator(
            _locked,
            numCheckpoints,
            _checkpoints,
            _delegates,
            _delegator,
            _delegatee,
            _owner
        );
    }

    function _checkpointDelegatee(uint256 _delegatee, uint256 balance_, bool _increase) internal {
        DelegationLogicLibrary.checkpointDelegatee(numCheckpoints, _checkpoints, _delegatee, balance_, _increase);
    }

    /// @notice Record user delegation checkpoints. Used by voting system.
    /// @dev Skips delegation if already delegated to `delegatee`.
    function _delegate(uint256 _delegator, uint256 _delegatee) internal {
        LockedBalance memory delegateLocked = _locked[_delegator];
        if (!delegateLocked.isPermanent) revert NotPermanentLock();
        if (_delegatee != 0 && _ownerOf(_delegatee) == address(0)) revert NonExistentToken();
        if (ownershipChange[_delegator] == block.number) revert OwnershipChange();
        if (_delegatee == _delegator) _delegatee = 0;
        uint256 currentDelegate = _delegates[_delegator];
        if (currentDelegate == _delegatee) return;

        uint256 delegatedBalance = delegateLocked.amount.toUint256();
        _checkpointDelegator(_delegator, _delegatee, _ownerOf(_delegator));
        _checkpointDelegatee(_delegatee, delegatedBalance, true);

        emit DelegateChanged(_msgSender(), currentDelegate, _delegatee);
    }

    /// @inheritdoc IVotingEscrow
    function delegate(uint256 delegator, uint256 delegatee) external {
        if (!_isApprovedOrOwner(_msgSender(), delegator)) revert NotApprovedOrOwner();
        return _delegate(delegator, delegatee);
    }

    /// @inheritdoc IVotingEscrow
    function delegateBySig(
        uint256 delegator,
        uint256 delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) revert InvalidSignatureS();
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegator, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        if (!_isApprovedOrOwner(signatory, delegator)) revert NotApprovedOrOwner();
        if (signatory == address(0)) revert InvalidSignature();
        if (nonce != nonces[signatory]++) revert InvalidNonce();
        if (block.timestamp > expiry) revert SignatureExpired();
        return _delegate(delegator, delegatee);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC6372 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVotingEscrow
    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @inheritdoc IVotingEscrow
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }
}
