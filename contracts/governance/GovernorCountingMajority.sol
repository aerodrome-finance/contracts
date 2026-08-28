// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {GovernorSimple} from "./GovernorSimple.sol";

/**
 * @dev Modified lightly from OpenZeppelin's GovernorCountingSimple to support a simple three option majority.
 *
 */
abstract contract GovernorCountingMajority is GovernorSimple {
    /**
     * @dev Supported vote types. Matches Governor Bravo ordering.
     */
    enum VoteType {
        Against,
        For,
        Abstain
    }

    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(uint256 => bool) hasVoted;
    }

    mapping(uint256 => ProposalVote) private _proposalVotes;

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @dev See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId, uint256 tokenId) public view virtual override returns (bool) {
        return _proposalVotes[proposalId].hasVoted[tokenId];
    }

    /**
     * @dev Accessor to the internal vote counts.
     */
    function proposalVotes(
        uint256 proposalId
    ) public view virtual returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        return (proposalVote.againstVotes, proposalVote.forVotes, proposalVote.abstainVotes);
    }

    /**
     * @dev Select winner of majority vote.
     */
    function _selectWinner(uint256 proposalId) internal view override returns (ProposalState) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        uint256 againstVotes = proposalVote.againstVotes;
        uint256 forVotes = proposalVote.forVotes;
        uint256 abstainVotes = proposalVote.abstainVotes;
        if ((againstVotes > forVotes) && (againstVotes > abstainVotes)) {
            return ProposalState.Defeated;
        } else if ((forVotes > againstVotes) && (forVotes > abstainVotes)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Expired;
        }
    }

    /**
     * @dev See {Governor-_countVote}. In this module, the support follows the `VoteType` enum (from Governor Bravo).
     */
    function _countVote(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        uint256 weight,
        bytes memory // params
    ) internal virtual override {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        require(!proposalVote.hasVoted[tokenId], "GovernorVotingSimple: vote already cast");
        require(weight > 0, "GovernorVotingSimple: zero voting weight");
        proposalVote.hasVoted[tokenId] = true;

        if (support == uint8(VoteType.Against)) {
            proposalVote.againstVotes += weight;
        } else if (support == uint8(VoteType.For)) {
            proposalVote.forVotes += weight;
        } else if (support == uint8(VoteType.Abstain)) {
            proposalVote.abstainVotes += weight;
        } else {
            revert("GovernorVotingSimple: invalid value for enum VoteType");
        }
    }
}
