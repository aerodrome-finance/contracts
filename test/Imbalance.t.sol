// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract ImbalanceTest is BaseTest {
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

        escrow = new VotingEscrow(address(forwarder), address(VELO), address(factoryRegistry));
        VeArtProxy artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));
    }

    function createLock() public {
        deployBaseCoins();

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.warp(1);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), TOKEN_1);
    }

    function votingEscrowMerge() public {
        createLock();

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        assertGt(escrow.balanceOfNFT(2), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), 2 * TOKEN_1);
        escrow.merge(2, 1);
        assertGt(escrow.balanceOfNFT(1), 1990039602248405587);
        assertEq(escrow.balanceOfNFT(2), 0);
    }

    function confirmTokensForFraxUsdc() public {
        votingEscrowMerge();
        deployFactories();
        factory.setFee(true, 1);
        factory.setFee(false, 1);
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
        assertEq(pool.token0(), token0);
        assertEq(pool.token1(), token1);
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

    function deployVoter() public {
        routerAddLiquidity();

        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));
        address[] memory tokens = new address[](4);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(VELO);
        voter.initialize(tokens, address(owner));

        assertEq(voter.length(), 0);
    }

    function deployPoolFactoryGauge() public {
        deployVoter();

        VELO.approve(address(gaugeFactory), 5 * TOKEN_100K);
        voter.createGauge(address(factory), address(pool3));
        assertFalse(voter.gauges(address(pool3)) == address(0));

        address gaugeAddr3 = voter.gauges(address(pool3));

        Gauge gauge3 = Gauge(gaugeAddr3);

        uint256 total = pool3.balanceOf(address(owner));
        pool3.approve(address(gauge3), total);
        gauge3.deposit(total);
        assertEq(gauge3.totalSupply(), total);
        assertEq(gauge3.earned(address(owner)), 0);
    }

    function testRouterPool3GetAmountsOutAndSwapExactTokensForTokens() public {
        deployPoolFactoryGauge();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(DAI), true, address(0));
        IRouter.Route[] memory routes2 = new IRouter.Route[](1);
        routes2[0] = IRouter.Route(address(DAI), address(FRAX), true, address(0));

        uint256 fb = FRAX.balanceOf(address(owner));
        uint256 db = DAI.balanceOf(address(owner));

        uint256 i;
        for (i = 0; i < 10; i++) {
            assertEq(router.getAmountsOut(1e25, routes)[1], pool3.getAmountOut(1e25, address(FRAX)));

            uint256[] memory expectedOutput = router.getAmountsOut(1e25, routes);
            FRAX.approve(address(router), 1e25);
            router.swapExactTokensForTokens(1e25, expectedOutput[1], routes, address(owner), block.timestamp);
        }

        DAI.approve(address(router), TOKEN_10B);
        FRAX.approve(address(router), TOKEN_10B);
        uint256 poolBefore = pool3.balanceOf(address(owner));
        router.addLiquidity(
            address(FRAX),
            address(DAI),
            true,
            TOKEN_10B,
            TOKEN_10B,
            0,
            0,
            address(owner),
            block.timestamp
        );
        uint256 poolAfter = pool3.balanceOf(address(owner));
        uint256 LPBal = poolAfter - poolBefore;

        for (i = 0; i < 10; i++) {
            assertEq(router.getAmountsOut(1e25, routes2)[1], pool3.getAmountOut(1e25, address(DAI)));

            uint256[] memory expectedOutput2 = router.getAmountsOut(1e25, routes2);
            DAI.approve(address(router), 1e25);
            router.swapExactTokensForTokens(1e25, expectedOutput2[1], routes2, address(owner), block.timestamp);
        }
        pool3.approve(address(router), LPBal);
        router.removeLiquidity(address(FRAX), address(DAI), true, LPBal, 0, 0, address(owner), block.timestamp);

        uint256 fa = FRAX.balanceOf(address(owner));
        uint256 da = DAI.balanceOf(address(owner));

        uint256 netAfter = fa + da;
        uint256 netBefore = db + fb;

        assertGt(netBefore, netAfter);
    }
}
