// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../script/DeployVelodromeV2.s.sol";
import "../script/DeployGaugesAndPoolsV2.s.sol";

import "./BaseTest.sol";

contract TestDeploy is BaseTest {
    using stdJson for string;
    using stdStorage for StdStorage;

    string public constantsFilename = vm.envString("CONSTANTS_FILENAME");
    string public jsonConstants;

    address public feeManager;
    address public team;
    address public emergencyCouncil;
    address public constant testDeployer = address(1);

    struct PoolV2 {
        bool stable;
        address tokenA;
        address tokenB;
    }

    struct PoolVeloV2 {
        bool stable;
        address token;
    }

    // Scripts to test
    DeployVelodromeV2 deployVelodromeV2;
    DeployGaugesAndPoolsV2 deployGaugesAndPoolsV2;

    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function _setUp() public override {
        _forkSetupBefore();

        deployVelodromeV2 = new DeployVelodromeV2();
        deployGaugesAndPoolsV2 = new DeployGaugesAndPoolsV2();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/");
        path = string.concat(path, constantsFilename);

        jsonConstants = vm.readFile(path);

        WETH = IWETH(abi.decode(vm.parseJson(jsonConstants, ".WETH"), (address)));
        team = abi.decode(vm.parseJson(jsonConstants, ".team"), (address));
        feeManager = abi.decode(vm.parseJson(jsonConstants, ".feeManager"), (address));
        emergencyCouncil = abi.decode(vm.parseJson(jsonConstants, ".emergencyCouncil"), (address));

        // Use test account for deployment
        stdstore.target(address(deployVelodromeV2)).sig("deployerAddress()").checked_write(testDeployer);
        stdstore.target(address(deployGaugesAndPoolsV2)).sig("deployerAddress()").checked_write(testDeployer);
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
        deployVelodromeV2.run();
        deployGaugesAndPoolsV2.run();

        assertEq(deployVelodromeV2.voter().epochGovernor(), team);
        assertEq(deployVelodromeV2.voter().governor(), team);

        // DeployVelodromeV2 checks

        // ensure all tokens are added to voter
        address[] memory _tokens = abi.decode(vm.parseJson(jsonConstants, ".whitelistTokens"), (address[]));
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            assertTrue(deployVelodromeV2.voter().isWhitelistedToken(token));
        }
        assertTrue(deployVelodromeV2.voter().isWhitelistedToken(address(deployVelodromeV2.VELO())));

        assertTrue(address(deployVelodromeV2.WETH()) == address(WETH));

        // PoolFactory
        assertEq(deployVelodromeV2.factory().voter(), address(deployVelodromeV2.voter()));
        assertEq(deployVelodromeV2.factory().stableFee(), 5);
        assertEq(deployVelodromeV2.factory().volatileFee(), 30);

        // v2 core
        // From _coreSetup()
        assertTrue(address(deployVelodromeV2.forwarder()) != address(0));
        assertEq(address(deployVelodromeV2.artProxy().ve()), address(deployVelodromeV2.escrow()));
        assertEq(deployVelodromeV2.escrow().voter(), address(deployVelodromeV2.voter()));
        assertEq(deployVelodromeV2.escrow().artProxy(), address(deployVelodromeV2.artProxy()));
        assertEq(address(deployVelodromeV2.distributor().ve()), address(deployVelodromeV2.escrow()));
        assertEq(deployVelodromeV2.router().defaultFactory(), address(deployVelodromeV2.factory()));
        assertEq(deployVelodromeV2.router().voter(), address(deployVelodromeV2.voter()));
        assertEq(address(deployVelodromeV2.router().weth()), address(WETH));
        assertEq(deployVelodromeV2.distributor().minter(), address(deployVelodromeV2.minter()));
        assertEq(deployVelodromeV2.VELO().minter(), address(deployVelodromeV2.minter()));

        assertEq(deployVelodromeV2.voter().minter(), address(deployVelodromeV2.minter()));
        assertEq(address(deployVelodromeV2.minter().velo()), address(deployVelodromeV2.VELO()));
        assertEq(address(deployVelodromeV2.minter().voter()), address(deployVelodromeV2.voter()));
        assertEq(address(deployVelodromeV2.minter().ve()), address(deployVelodromeV2.escrow()));
        assertEq(address(deployVelodromeV2.minter().rewardsDistributor()), address(deployVelodromeV2.distributor()));

        // Permissions
        assertEq(deployVelodromeV2.escrow().team(), team);
        assertEq(deployVelodromeV2.escrow().allowedManager(), team);
        assertEq(deployVelodromeV2.factory().pauser(), team);
        assertEq(deployVelodromeV2.voter().emergencyCouncil(), emergencyCouncil);
        assertEq(deployVelodromeV2.voter().governor(), team);
        assertEq(deployVelodromeV2.voter().epochGovernor(), team);
        assertEq(deployVelodromeV2.factoryRegistry().owner(), team);
        assertEq(deployVelodromeV2.factory().feeManager(), feeManager);

        // DeployGaugesAndPoolsV2 checks

        // Validate non-VELO pools and gauges
        PoolV2[] memory poolsV2 = abi.decode(jsonConstants.parseRaw(".poolsV2"), (PoolV2[]));
        for (uint256 i = 0; i < poolsV2.length; i++) {
            PoolV2 memory p = poolsV2[i];
            address poolAddr = deployVelodromeV2.factory().getPool(p.tokenA, p.tokenB, p.stable);
            assertTrue(poolAddr != address(0));
            address gaugeAddr = deployVelodromeV2.voter().gauges(poolAddr);
            assertTrue(gaugeAddr != address(0));
        }

        // validate VELO pools and gauges
        PoolVeloV2[] memory poolsVeloV2 = abi.decode(jsonConstants.parseRaw(".poolsVeloV2"), (PoolVeloV2[]));
        for (uint256 i = 0; i < poolsVeloV2.length; i++) {
            PoolVeloV2 memory p = poolsVeloV2[i];
            address poolAddr = deployVelodromeV2.factory().getPool(
                address(deployVelodromeV2.VELO()),
                p.token,
                p.stable
            );
            assertTrue(poolAddr != address(0));
            address gaugeAddr = deployVelodromeV2.voter().gauges(poolAddr);
            assertTrue(gaugeAddr != address(0));
        }
    }
}
