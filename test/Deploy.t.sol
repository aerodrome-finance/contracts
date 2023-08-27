// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../script/DeployCore.s.sol";
import "../script/DistributeAirdrops.s.sol";
import "../script/DeployGaugesAndPools.s.sol";

import "./BaseTest.sol";

contract TestDeploy is BaseTest {
    using stdJson for string;
    using stdStorage for StdStorage;
    using SafeCastLibrary for int128;

    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public airdropFilename = vm.envString("AIRDROPS_FILENAME");
    string public root = vm.projectRoot();
    string public jsonConstants;

    address public feeManager;
    address public team;
    address public emergencyCouncil;
    address public constant testDeployer = address(1);

    struct PoolNonAero {
        bool stable;
        address tokenA;
        address tokenB;
    }

    struct PoolAero {
        bool stable;
        address token;
    }

    // Scripts to test
    DeployCore deployCore;
    DistributeAirdrops distributeAirdrops;
    DeployGaugesAndPools deployGaugesAndPools;

    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function _setUp() public override {
        _forkSetupBefore();

        deployCore = new DeployCore();
        deployGaugesAndPools = new DeployGaugesAndPools();

        string memory path = string.concat(root, "/script/constants/");
        path = string.concat(path, constantsFilename);

        jsonConstants = vm.readFile(path);

        WETH = IWETH(abi.decode(vm.parseJson(jsonConstants, ".WETH"), (address)));
        team = abi.decode(vm.parseJson(jsonConstants, ".team"), (address));
        feeManager = abi.decode(vm.parseJson(jsonConstants, ".feeManager"), (address));
        emergencyCouncil = abi.decode(vm.parseJson(jsonConstants, ".emergencyCouncil"), (address));

        // Use test account for deployment
        stdstore.target(address(deployCore)).sig("deployerAddress()").checked_write(testDeployer);
        stdstore.target(address(deployGaugesAndPools)).sig("deployerAddress()").checked_write(testDeployer);
        vm.deal(testDeployer, TOKEN_10K);
    }

    function testLoadedState() public {
        // If tests fail at this point- you need to set the .env and the constants used for deployment.
        // Refer to script/README.md
        assertTrue(address(WETH) != address(0));
        assertTrue(team != address(0));
        assertTrue(feeManager != address(0));
        assertTrue(emergencyCouncil != address(0));
    }

    function testDeployScript() public {
        deployCore.run();
        deployGaugesAndPools.run();
        distributeAirdrops = new DistributeAirdrops();
        stdstore.target(address(distributeAirdrops)).sig("deployerAddress()").checked_write(testDeployer);

        assertEq(deployCore.voter().epochGovernor(), team);
        assertEq(deployCore.voter().governor(), team);

        // DeployCore checks

        // ensure all tokens are added to voter
        address[] memory _tokens = abi.decode(vm.parseJson(jsonConstants, ".whitelistTokens"), (address[]));
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            assertTrue(deployCore.voter().isWhitelistedToken(token));
        }
        assertTrue(deployCore.voter().isWhitelistedToken(address(deployCore.AERO())));

        assertTrue(address(deployCore.WETH()) == address(WETH));

        // PoolFactory
        assertEq(deployCore.factory().voter(), address(deployCore.voter()));
        assertEq(deployCore.factory().stableFee(), 5);
        assertEq(deployCore.factory().volatileFee(), 30);

        // Minter Distribution checks
        assertTrue(deployCore.minter().initialized());
        AirdropDistributor airdrop = deployCore.airdrop();

        // Loads Liquid Airdrop information
        DeployCore.AirdropInfo[] memory infos = abi.decode(
            jsonConstants.parseRaw(".minter.liquid"),
            (DeployCore.AirdropInfo[])
        );
        (address[] memory liquidWallets, uint256[] memory liquidAmounts) = deployCore._getLiquidAirdropInfo(
            address(airdrop),
            deployCore.AIRDROPPER_BALANCE(),
            infos
        );

        // Loads Locked Airdrop information
        infos = abi.decode(jsonConstants.parseRaw(".minter.locked"), (DeployCore.AirdropInfo[]));
        (address[] memory lockedWallets, uint256[] memory lockedAmounts) = deployCore._getLockedAirdropInfo(infos);

        // Ensures Liquid Tokens were minted correctly
        uint256 len = liquidWallets.length;
        for (uint256 i = 0; i < len; i++) {
            assertEq(deployCore.AERO().balanceOf(liquidWallets[i]), liquidAmounts[i]);
        }

        // Ensures permanently locked NFTs were distributed correctly
        len = lockedWallets.length;
        uint256 tokenId;
        for (uint256 i = 0; i < len; i++) {
            tokenId = i + 1;
            assertEq(deployCore.escrow().ownerOf(tokenId), lockedWallets[i]);
            IVotingEscrow.LockedBalance memory locked = deployCore.escrow().locked(tokenId);
            assertEq(locked.amount.toUint256(), lockedAmounts[i]);
            assertTrue(locked.isPermanent);
            assertEq(locked.end, 0);
        }

        // core
        // From _coreSetup()
        assertTrue(address(deployCore.forwarder()) != address(0));
        assertEq(address(deployCore.artProxy().ve()), address(deployCore.escrow()));
        assertEq(deployCore.escrow().voter(), address(deployCore.voter()));
        assertEq(deployCore.escrow().artProxy(), address(deployCore.artProxy()));
        assertEq(address(deployCore.distributor().ve()), address(deployCore.escrow()));
        assertEq(deployCore.router().defaultFactory(), address(deployCore.factory()));
        assertEq(deployCore.router().voter(), address(deployCore.voter()));
        assertEq(address(deployCore.router().weth()), address(WETH));
        assertEq(deployCore.distributor().minter(), address(deployCore.minter()));
        assertEq(deployCore.AERO().minter(), address(deployCore.minter()));

        assertEq(deployCore.voter().minter(), address(deployCore.minter()));
        assertEq(address(deployCore.minter().aero()), address(deployCore.AERO()));
        assertEq(address(deployCore.minter().voter()), address(deployCore.voter()));
        assertEq(address(deployCore.minter().ve()), address(deployCore.escrow()));
        assertEq(address(deployCore.minter().rewardsDistributor()), address(deployCore.distributor()));

        // Permissions
        assertEq(address(deployCore.minter().pendingTeam()), team);
        assertEq(deployCore.escrow().team(), team);
        assertEq(deployCore.escrow().allowedManager(), team);
        assertEq(deployCore.factory().pauser(), team);
        assertEq(deployCore.voter().emergencyCouncil(), emergencyCouncil);
        assertEq(deployCore.voter().governor(), team);
        assertEq(deployCore.voter().epochGovernor(), team);
        assertEq(deployCore.factoryRegistry().owner(), team);
        assertEq(deployCore.factory().feeManager(), feeManager);

        // DeployGaugesAndPools checks

        // Validate non-AERO pools and gauges
        PoolNonAero[] memory pools = abi.decode(jsonConstants.parseRaw(".pools"), (PoolNonAero[]));
        for (uint256 i = 0; i < pools.length; i++) {
            PoolNonAero memory p = pools[i];
            address poolAddr = deployCore.factory().getPool(p.tokenA, p.tokenB, p.stable);
            assertTrue(poolAddr != address(0));
            address gaugeAddr = deployCore.voter().gauges(poolAddr);
            assertTrue(gaugeAddr != address(0));
        }

        // validate AERO pools and gauges
        PoolAero[] memory poolsAero = abi.decode(jsonConstants.parseRaw(".poolsAero"), (PoolAero[]));
        for (uint256 i = 0; i < poolsAero.length; i++) {
            PoolAero memory p = poolsAero[i];
            address poolAddr = deployCore.factory().getPool(address(deployCore.AERO()), p.token, p.stable);
            assertTrue(poolAddr != address(0));
            address gaugeAddr = deployCore.voter().gauges(poolAddr);
            assertTrue(gaugeAddr != address(0));
        }

        // DistributeAirdrops checks

        // Test Airdrop Deployment
        IVotingEscrow escrow = airdrop.ve();
        assertEq(airdrop.owner(), deployCore.minter().team());
        assertEq(address(airdrop), address(deployCore.airdrop()));
        assertEq(address(airdrop.ve()), address(deployCore.escrow()));
        assertEq(address(airdrop.aero()), address(deployCore.AERO()));
        assertEq(airdrop.aero().balanceOf(address(airdrop)), deployCore.AIRDROPPER_BALANCE());
        assertEq(deployCore.escrow().balanceOf(address(airdrop)), 0);

        stdstore.target(address(distributeAirdrops)).sig("WALLET_BATCH_SIZE()").checked_write(2);
        distributeAirdrops.run();

        // Test Airdrop Distribution
        assertEq(airdrop.owner(), address(0));
        string memory airdropPath = string.concat(root, "/script/constants/");
        airdropPath = string.concat(airdropPath, airdropFilename);
        jsonConstants = vm.readFile(airdropPath);
        infos = abi.decode(jsonConstants.parseRaw(".airdrop"), (DeployCore.AirdropInfo[]));
        len = distributeAirdrops.MAX_AIRDROPS() < infos.length ? distributeAirdrops.MAX_AIRDROPS() : infos.length;

        // Validates all emissioned Locked NFTs
        uint256 firstAirdroppedToken = escrow.tokenId() - len;
        address _wallet;
        uint256 _amount;
        for (uint256 i = 0; i < len; i++) {
            DeployCore.AirdropInfo memory drop = infos[i];
            _wallet = drop.wallet;
            _amount = drop.amount;
            tokenId = i + 1 + firstAirdroppedToken; // Skipping locks minted by Minter
            assertEq(escrow.ownerOf(tokenId), _wallet);
            IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
            assertEq(locked.amount.toUint256(), _amount);
            assertTrue(locked.isPermanent);
            assertEq(locked.end, 0);
        }
    }
}
