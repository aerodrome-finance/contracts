// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ManagedRewardsFactory} from "contracts/factories/ManagedRewardsFactory.sol";
import {VotingRewardsFactory} from "contracts/factories/VotingRewardsFactory.sol";
import {GaugeFactory} from "contracts/factories/GaugeFactory.sol";
import {PoolFactory, IPoolFactory} from "contracts/factories/PoolFactory.sol";
import {IFactoryRegistry, FactoryRegistry} from "contracts/factories/FactoryRegistry.sol";
import {Pool} from "contracts/Pool.sol";
import {IMinter, Minter} from "contracts/Minter.sol";
import {IReward, Reward} from "contracts/rewards/Reward.sol";
import {FeesVotingReward} from "contracts/rewards/FeesVotingReward.sol";
import {BribeVotingReward} from "contracts/rewards/BribeVotingReward.sol";
import {FreeManagedReward} from "contracts/rewards/FreeManagedReward.sol";
import {LockedManagedReward} from "contracts/rewards/LockedManagedReward.sol";
import {IGauge, Gauge} from "contracts/gauges/Gauge.sol";
import {PoolFees} from "contracts/PoolFees.sol";
import {RewardsDistributor, IRewardsDistributor} from "contracts/RewardsDistributor.sol";
import {IRouter, Router} from "contracts/Router.sol";
import {IVelo, Velo} from "contracts/Velo.sol";
import {IVoter, Voter} from "contracts/Voter.sol";
import {VeArtProxy} from "contracts/VeArtProxy.sol";
import {IVotingEscrow, VotingEscrow} from "contracts/VotingEscrow.sol";
import {VeloGovernor} from "contracts/VeloGovernor.sol";
import {EpochGovernor} from "contracts/EpochGovernor.sol";
import {SafeCastLibrary} from "contracts/libraries/SafeCastLibrary.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SigUtils} from "test/utils/SigUtils.sol";
import {Forwarder} from "@opengsn/contracts/src/forwarder/Forwarder.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

/// @notice Base contract used for tests and deployment scripts
abstract contract Base is Script, Test {
    enum Deployment {
        DEFAULT,
        FORK,
        CUSTOM
    }
    /// @dev Determines whether or not to use the base set up configuration
    ///      Local v2 deployment used by default
    Deployment deploymentType;

    IWETH public WETH;
    Velo public VELO;
    address[] public tokens;

    /// @dev Core v2 Deployment
    Forwarder public forwarder;
    Pool public implementation;
    Router public router;
    VotingEscrow public escrow;
    VeArtProxy public artProxy;
    PoolFactory public factory;
    FactoryRegistry public factoryRegistry;
    GaugeFactory public gaugeFactory;
    VotingRewardsFactory public votingRewardsFactory;
    ManagedRewardsFactory public managedRewardsFactory;
    Voter public voter;
    RewardsDistributor public distributor;
    Minter public minter;
    Gauge public gauge;
    VeloGovernor public governor;
    EpochGovernor public epochGovernor;

    /// @dev Global address to set
    address public allowedManager;

    function _coreSetup() public {
        deployFactories();

        forwarder = new Forwarder();

        escrow = new VotingEscrow(address(forwarder), address(VELO), address(factoryRegistry));
        artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));

        // Setup voter and distributor
        distributor = new RewardsDistributor(address(escrow));
        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));

        escrow.setVoterAndDistributor(address(voter), address(distributor));
        escrow.setAllowedManager(allowedManager);

        // Setup router
        router = new Router(
            address(forwarder),
            address(factoryRegistry),
            address(factory),
            address(voter),
            address(WETH)
        );

        // Setup minter
        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setMinter(address(minter));
        VELO.setMinter(address(minter));

        /// @dev tokens are already set in the respective setupBefore()
        voter.initialize(tokens, address(minter));
    }

    function deployFactories() public {
        implementation = new Pool();
        factory = new PoolFactory(address(implementation));

        votingRewardsFactory = new VotingRewardsFactory();
        gaugeFactory = new GaugeFactory();
        managedRewardsFactory = new ManagedRewardsFactory();
        factoryRegistry = new FactoryRegistry(
            address(factory),
            address(votingRewardsFactory),
            address(gaugeFactory),
            address(managedRewardsFactory)
        );
    }
}
