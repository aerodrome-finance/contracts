// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IManagedRewardsFactory {
    event ManagedRewardCreated(
        address indexed voter,
        address indexed lockedManagedReward,
        address indexed freeManagedReward
    );

    /// @notice creates a LockedManagedReward and a FreeManagedReward contract for a managed veNFT
    /// @param _forwarder Address of trusted forwarder
    /// @param _voter Address of Voter.sol
    /// @return lockedManagedReward Address of LockedManagedReward contract created
    /// @return freeManagedReward   Address of FreeManagedReward contract created
    function createRewards(
        address _forwarder,
        address _voter
    ) external returns (address lockedManagedReward, address freeManagedReward);
}
