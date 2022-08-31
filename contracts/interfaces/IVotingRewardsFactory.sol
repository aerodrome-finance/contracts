// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVotingRewardsFactory {
    /// @notice creates a BribeVotingReward and a FeesVotingReward contract for a gauge
    /// @param rewards              Addresses of pair tokens to be used as valid rewards tokens
    /// @return feesVotingReward    Address of FeesVotingReward contract created
    /// @return bribeVotingReward   Address of BribeVotingReward contract created
    function createRewards(address[] memory rewards)
        external
        returns (address feesVotingReward, address bribeVotingReward);
}
