// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ManagedReward} from "./ManagedReward.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IVoter} from "../interfaces/IVoter.sol";

/// @notice Stores rewards that are free to be distributed
/// @dev Rewards are distributed based on weight contribution to managed nft
contract FreeManagedReward is ManagedReward {
    constructor(address _forwarder, address _voter) ManagedReward(_forwarder, _voter) {}

    /// @inheritdoc ManagedReward
    function getReward(uint256 tokenId, address[] memory tokens) external override nonReentrant {
        if (!IVotingEscrow(ve).isApprovedOrOwner(_msgSender(), tokenId)) revert NotAuthorized();

        address owner = IVotingEscrow(ve).ownerOf(tokenId);

        _getReward(owner, tokenId, tokens);
    }

    /// @inheritdoc ManagedReward
    function notifyRewardAmount(address token, uint256 amount) external override nonReentrant {
        address sender = _msgSender();
        if (!isReward[token]) {
            if (!IVoter(voter).isWhitelistedToken(token)) revert NotWhitelisted();
            isReward[token] = true;
            rewards.push(token);
        }

        _notifyRewardAmount(sender, token, amount);
    }
}
