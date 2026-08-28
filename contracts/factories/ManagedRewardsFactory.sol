// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IManagedRewardsFactory} from "../interfaces/factories/IManagedRewardsFactory.sol";
import {FreeManagedReward} from "../rewards/FreeManagedReward.sol";
import {LockedManagedReward} from "../rewards/LockedManagedReward.sol";

contract ManagedRewardsFactory is IManagedRewardsFactory {
    /// @inheritdoc IManagedRewardsFactory
    function createRewards(
        address _forwarder,
        address _voter
    ) external returns (address lockedManagedReward, address freeManagedReward) {
        lockedManagedReward = address(new LockedManagedReward(_forwarder, _voter));
        freeManagedReward = address(new FreeManagedReward(_forwarder, _voter));
        emit ManagedRewardCreated(_voter, lockedManagedReward, freeManagedReward);
    }
}
