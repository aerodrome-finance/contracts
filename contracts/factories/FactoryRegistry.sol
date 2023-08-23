// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFactoryRegistry} from "../interfaces/factories/IFactoryRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Protocol Factory Registry
/// @author Carter Carlson (@pegahcarter)
/// @notice Protocol Factory Registry to swap and create gauges
contract FactoryRegistry is IFactoryRegistry, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev factory to create free and locked rewards for a managed veNFT
    address private _managedRewardsFactory;

    /// @dev The protocol will always have a usable poolFactory, votingRewardsFactory, and gaugeFactory.  The votingRewardsFactory
    // and gaugeFactory are defined to the poolFactory which can never be removed
    address public immutable fallbackPoolFactory;

    /// @dev Array of poolFactories used to create a gauge and votingRewards
    EnumerableSet.AddressSet private _poolFactories;

    struct FactoriesToPoolFactory {
        address votingRewardsFactory;
        address gaugeFactory;
    }
    /// @dev the factories linked to the poolFactory
    mapping(address => FactoriesToPoolFactory) private _factoriesToPoolsFactory;

    constructor(
        address _fallbackPoolFactory,
        address _fallbackVotingRewardsFactory,
        address _fallbackGaugeFactory,
        address _newManagedRewardsFactory
    ) {
        fallbackPoolFactory = _fallbackPoolFactory;

        approve(_fallbackPoolFactory, _fallbackVotingRewardsFactory, _fallbackGaugeFactory);
        setManagedRewardsFactory(_newManagedRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function approve(address poolFactory, address votingRewardsFactory, address gaugeFactory) public onlyOwner {
        if (poolFactory == address(0) || votingRewardsFactory == address(0) || gaugeFactory == address(0))
            revert ZeroAddress();
        if (_poolFactories.contains(poolFactory)) revert PathAlreadyApproved();

        FactoriesToPoolFactory memory usedFactories = _factoriesToPoolsFactory[poolFactory];

        // If the poolFactory *has not* been approved before, can approve any gauge/votingRewards factory
        // Only one check is sufficient
        if (usedFactories.votingRewardsFactory == address(0)) {
            _factoriesToPoolsFactory[poolFactory] = FactoriesToPoolFactory(votingRewardsFactory, gaugeFactory);
        } else {
            // If the poolFactory *has* been approved before, can only approve the same used gauge/votingRewards factory to
            //     to maintain state within Voter
            if (
                votingRewardsFactory != usedFactories.votingRewardsFactory || gaugeFactory != usedFactories.gaugeFactory
            ) revert InvalidFactoriesToPoolFactory();
        }

        _poolFactories.add(poolFactory);
        emit Approve(poolFactory, votingRewardsFactory, gaugeFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function unapprove(address poolFactory) external onlyOwner {
        if (poolFactory == fallbackPoolFactory) revert FallbackFactory();
        if (!_poolFactories.contains(poolFactory)) revert PathNotApproved();
        _poolFactories.remove(poolFactory);
        (address votingRewardsFactory, address gaugeFactory) = factoriesToPoolFactory(poolFactory);
        emit Unapprove(poolFactory, votingRewardsFactory, gaugeFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function setManagedRewardsFactory(address _newManagedRewardsFactory) public onlyOwner {
        if (_newManagedRewardsFactory == _managedRewardsFactory) revert SameAddress();
        if (_newManagedRewardsFactory == address(0)) revert ZeroAddress();
        _managedRewardsFactory = _newManagedRewardsFactory;
        emit SetManagedRewardsFactory(_newManagedRewardsFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function managedRewardsFactory() external view returns (address) {
        return _managedRewardsFactory;
    }

    /// @inheritdoc IFactoryRegistry
    function factoriesToPoolFactory(
        address poolFactory
    ) public view returns (address votingRewardsFactory, address gaugeFactory) {
        FactoriesToPoolFactory memory f = _factoriesToPoolsFactory[poolFactory];
        votingRewardsFactory = f.votingRewardsFactory;
        gaugeFactory = f.gaugeFactory;
    }

    /// @inheritdoc IFactoryRegistry
    function poolFactories() external view returns (address[] memory) {
        return _poolFactories.values();
    }

    /// @inheritdoc IFactoryRegistry
    function isPoolFactoryApproved(address poolFactory) external view returns (bool) {
        return _poolFactories.contains(poolFactory);
    }

    /// @inheritdoc IFactoryRegistry
    function poolFactoriesLength() external view returns (uint256) {
        return _poolFactories.length();
    }
}
