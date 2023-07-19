// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract OracleTest is BaseTest {
    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function deployBaseCoins() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e25;
        mintToken(address(VELO), owners, amounts);
        escrow = VotingEscrow(address(VELO));
    }

    function confirmTokensForFraxUsdc() public {
        deployBaseCoins();
        deployFactories();
        factory.setFee(true, 1);
        factory.setFee(false, 1);

        escrow = new VotingEscrow(address(forwarder), address(VELO), address(factoryRegistry));
        VeArtProxy artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));
        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));
        router = new Router(
            address(forwarder),
            address(factoryRegistry),
            address(factory),
            address(voter),
            address(WETH)
        );
        deployPoolWithOwner(address(owner));

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq((pool.token0()), token0);
        assertEq((pool.token1()), token1);
    }

    function mintAndBurnTokensForPoolFraxUsdc() public {
        confirmTokensForFraxUsdc();

        USDC.transfer(address(pool), USDC_1);
        FRAX.transfer(address(pool), TOKEN_1);
        pool.mint(address(owner));
        assertEq(pool.getAmountOut(USDC_1, address(USDC)), 945128557522723966);
    }

    function routerAddLiquidity() public {
        mintAndBurnTokensForPoolFraxUsdc();

        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(
            address(FRAX),
            address(USDC),
            true,
            TOKEN_100K,
            USDC_100K,
            TOKEN_100K,
            USDC_100K,
            address(owner),
            block.timestamp
        );
        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.addLiquidity(
            address(FRAX),
            address(USDC),
            false,
            TOKEN_100K,
            USDC_100K,
            TOKEN_100K,
            USDC_100K,
            address(owner),
            block.timestamp
        );
        DAI.approve(address(router), TOKEN_100M);
        FRAX.approve(address(router), TOKEN_100M);
        router.addLiquidity(
            address(FRAX),
            address(DAI),
            true,
            TOKEN_100M,
            TOKEN_100M,
            0,
            0,
            address(owner),
            block.timestamp
        );
    }

    function routerPool1GetAmountsOutAndSwapExactTokensForTokens() public {
        routerAddLiquidity();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pool.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory asserted_output = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, asserted_output[1], routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, 0, routes, address(owner), block.timestamp);
        address poolFees = pool.poolFees();
        assertEq(USDC.balanceOf(poolFees), 400);
        uint256 b = USDC.balanceOf(address(owner));
        pool.claimFees();
        assertGt(USDC.balanceOf(address(owner)), b);
    }

    function testOracle() public {
        routerPool1GetAmountsOutAndSwapExactTokensForTokens();

        assertEq(pool.quote(address(USDC), 1e9, 1), 999999494004424240546);
        assertEq(pool.quote(address(FRAX), 1e21, 1), 999999506);
    }
}
