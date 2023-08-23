// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVotes} from "./governance/IVotes.sol";
import {IVotingEscrow} from "contracts/interfaces/IVotingEscrow.sol";

import {IVetoGovernor} from "./governance/IVetoGovernor.sol";
import {VetoGovernor} from "./governance/VetoGovernor.sol";
import {VetoGovernorCountingSimple} from "./governance/VetoGovernorCountingSimple.sol";
import {VetoGovernorVotes} from "./governance/VetoGovernorVotes.sol";
import {VetoGovernorVotesQuorumFraction} from "./governance/VetoGovernorVotesQuorumFraction.sol";

/// @title ProtocolGovernor
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Protocol governance with timestamp-based voting power from VotingEscrow NFTs
///         Supports vetoing of proposals as mitigation for 51% attacks
///         Votes are cast and counted on a per tokenId basis
contract ProtocolGovernor is
    VetoGovernor,
    VetoGovernorCountingSimple,
    VetoGovernorVotes,
    VetoGovernorVotesQuorumFraction
{
    address public immutable ve;
    address public vetoer;
    address public pendingVetoer;
    uint256 public constant MAX_PROPOSAL_NUMERATOR = 500; // max 5%
    uint256 public constant PROPOSAL_DENOMINATOR = 10_000;
    uint256 public proposalNumerator = 2; // start at 0.02%

    error NotTeam();
    error NotPendingVetoer();
    error NotVetoer();
    error ProposalNumeratorTooHigh();
    error ZeroAddress();

    constructor(
        IVotes _ve
    )
        VetoGovernor("Protocol Governor")
        VetoGovernorVotes(_ve)
        VetoGovernorVotesQuorumFraction(4) // 4%
    {
        ve = address(_ve);
        vetoer = msg.sender;
    }

    function votingDelay() public pure override(IVetoGovernor) returns (uint256) {
        return (15 minutes);
    }

    function votingPeriod() public pure override(IVetoGovernor) returns (uint256) {
        return (1 weeks);
    }

    function setProposalNumerator(uint256 numerator) external {
        if (msg.sender != IVotingEscrow(ve).team()) revert NotTeam();
        if (numerator > MAX_PROPOSAL_NUMERATOR) revert ProposalNumeratorTooHigh();
        proposalNumerator = numerator;
    }

    function proposalThreshold() public view override(VetoGovernor) returns (uint256) {
        return (token.getPastTotalSupply(block.timestamp - 1) * proposalNumerator) / PROPOSAL_DENOMINATOR;
    }

    /// @dev Vetoer can be removed once the risk of a 51% attack becomes unfeasible.
    ///      This can be done by transferring ownership of vetoer to a contract that is "bricked"
    ///      i.e. a non-zero address contract that is immutable with no ability to call this function.
    function setVetoer(address _vetoer) external {
        if (msg.sender != vetoer) revert NotVetoer();
        if (_vetoer == address(0)) revert ZeroAddress();
        pendingVetoer = _vetoer;
    }

    function acceptVetoer() external {
        if (msg.sender != pendingVetoer) revert NotPendingVetoer();
        vetoer = pendingVetoer;
        delete pendingVetoer;
    }

    /// @notice Support for vetoer to protect against 51% attacks
    function veto(uint256 _proposalId) external {
        if (msg.sender != vetoer) revert NotVetoer();
        _veto(_proposalId);
    }

    function renounceVetoer() external {
        if (msg.sender != vetoer) revert NotVetoer();
        delete vetoer;
    }
}
