// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract ZapTest is BaseTest {
    Router _router;
    Pool vPool;
    Gauge vGauge;
    Pool sPool;
    Gauge sGauge;
    uint256 constant feeRate = 30; // .3% fee for volatile pools on mainnet

    /// @dev Volatile slippage (.5%)
    uint256 constant vSLIPPAGE = 50;
    /// @dev Stable slippage (.2%)
    uint256 constant sSLIPPAGE = 20;
    /// @dev ETH price for current pool ratio
    uint256 constant ETH_PRICE = 1638;
    // @dev 2.5 tokens with 6 decimals
    uint256 constant USDC_2_5 = 2.5e6;

    constructor() {
        deploymentType = Deployment.DEFAULT;
    }

    function _setUp() public override {
        uint256[] memory amounts = new uint256[](1);
        address[] memory ownerAddr = new address[](1);
        amounts[0] = 1e35;
        ownerAddr[0] = address(owner);
        mintToken(address(WETH), ownerAddr, amounts);
        _addLiquidityToPool(
            address(owner),
            address(router),
            address(WETH),
            address(USDC),
            false,
            TOKEN_1 * 763,
            USDC_10K * 125
        );

        _addLiquidityToPool(
            address(owner),
            address(router),
            address(FRAX),
            address(USDC),
            true,
            TOKEN_100K * 10,
            USDC_100K * 10
        );

        // Current State:
        // 1.25m USDC, 763 WETH, current WETH price ~$1638
        // Pool has slightly more USDC than WETH
        vPool = Pool(factory.getPool(address(USDC), address(WETH), false));

        /// Current State:
        /// ~1m FRAX, ~1m USDC
        sPool = Pool(factory.getPool(address(FRAX), address(USDC), true));

        deal(address(USDC), address(owner2), USDC_1 * 1e6);
        vm.deal(address(owner2), TOKEN_100K);

        _router = new Router(
            address(forwarder),
            address(factoryRegistry),
            address(factory),
            address(voter),
            address(WETH)
        );
        vm.startPrank(address(governor));
        vGauge = Gauge(voter.createGauge(address(factory), address(vPool)));
        sGauge = Gauge(voter.gauges(address(sPool)));
        vm.stopPrank();

        vm.label(address(vPool), "vAMM WETH/USDC");
        vm.label(address(sPool), "sAMM FRAX/USDC");
        vm.label(address(vGauge), "vAMM Gauge");
        vm.label(address(sGauge), "sAMM Gauge");
        vm.label(address(_router), "Router");
    }

    function testZapInWithStablePool() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(owner2));
        uint256 usdcPoolPreBal = USDC.balanceOf(address(sPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPreBal = FRAX.balanceOf(address(owner2));
        assertEq(sPool.balanceOf(address(owner2)), 0);

        uint256 ratio = _router.quoteStableLiquidityRatio(address(FRAX), address(USDC), address(factory));
        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(FRAX), true, address(factory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPool = _createZapInParams(
            address(FRAX),
            address(USDC),
            true,
            address(factory),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            routesA,
            routesB
        );

        _router.zapIn(
            address(USDC),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            zapInPool,
            routesA,
            routesB,
            address(owner2),
            false
        );

        uint256 usdcPoolPostBal = USDC.balanceOf(address(sPool));
        uint256 usdcOwnerPostBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPostBal = FRAX.balanceOf(address(owner2));

        assertApproxEqAbs(usdcPoolPostBal - usdcPoolPreBal, USDC_10K, USDC_2_5);
        assertApproxEqAbs(usdcOwnerPreBal - usdcOwnerPostBal, USDC_10K, USDC_1);
        assertLt(fraxOwnerPostBal - fraxOwnerPreBal, (TOKEN_100K * 150) / MAX_BPS);
        assertGt(sPool.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(FRAX.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapAndStakeWithStablePool() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPoolPreBal = USDC.balanceOf(address(sPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPreBal = FRAX.balanceOf(address(owner2));
        assertEq(sPool.balanceOf(address(owner2)), 0);
        assertEq(sPool.balanceOf(address(sGauge)), 0);
        assertEq(sGauge.balanceOf(address(owner2)), 0);

        uint256 ratio = _router.quoteStableLiquidityRatio(address(FRAX), address(USDC), address(factory));
        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(FRAX), true, address(factory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPool = _createZapInParams(
            address(FRAX),
            address(USDC),
            true,
            address(factory),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            routesA,
            routesB
        );

        _router.zapIn(
            address(USDC),
            (USDC_10K * (1e18 - ratio)) / 1e18,
            (USDC_10K * ratio) / 1e18,
            zapInPool,
            routesA,
            routesB,
            address(owner2),
            true
        );

        uint256 usdcPoolPostBal = USDC.balanceOf(address(sPool));
        uint256 usdcOwnerPostBal = USDC.balanceOf(address(owner2));
        uint256 fraxOwnerPostBal = FRAX.balanceOf(address(owner2));

        assertApproxEqAbs(usdcPoolPostBal - usdcPoolPreBal, USDC_10K, USDC_2_5);
        assertApproxEqAbs(usdcOwnerPreBal - usdcOwnerPostBal, USDC_10K, USDC_1);
        assertLt(fraxOwnerPostBal - fraxOwnerPreBal, (TOKEN_100K * 150) / MAX_BPS);
        assertEq(sPool.balanceOf(address(owner2)), 0);
        assertGt(sPool.balanceOf(address(sGauge)), 0);
        assertGt(sGauge.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(FRAX.balanceOf(address(_router)), 0);
        assertEq(sPool.allowance(address(_router), address(sGauge)), 0);
        vm.stopPrank();
    }

    function testCannotZapWithETHWithInvalidParameters() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        IRouter.Zap memory zapInPool = IRouter.Zap(address(WETH), address(USDC), false, address(factory), 0, 0, 0, 0);

        // tokenIn != WETH
        vm.expectRevert(IRouter.InvalidTokenInForETHDeposit.selector);
        _router.zapIn{value: TOKEN_1}(
            address(0),
            TOKEN_1 / 2,
            TOKEN_1 / 2,
            zapInPool,
            routesA,
            routesB,
            address(owner2),
            true
        );

        // msg.value != zapAmount
        vm.expectRevert(IRouter.InvalidAmountInForETHDeposit.selector);
        _router.zapIn{value: TOKEN_1}(
            ETHER,
            TOKEN_1 / 2,
            TOKEN_1 / 4,
            zapInPool,
            routesA,
            routesB,
            address(owner2),
            true
        );

        vm.stopPrank();
    }

    function testZapInWithVolatilePool() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPoolPreBal = USDC.balanceOf(address(vPool));
        uint256 wethPoolPreBal = WETH.balanceOf(address(vPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertEq(vPool.balanceOf(address(owner3)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(factory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPool = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(factory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zapInPool, routesA, routesB, address(owner3), false);

        uint256 fee = ((USDC_10K / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertEq(USDC.balanceOf(address(vPool)) - usdcPoolPreBal, USDC_10K - fee);
        assertEq(usdcOwnerPreBal - USDC.balanceOf(address(owner2)), USDC_10K);
        assertLt(wethPoolPreBal - WETH.balanceOf(address(vPool)), slippage);
        assertEq(address(owner2).balance, ethOwnerPreBal);
        assertLt(WETH.balanceOf(address(owner2)) - wethOwnerPreBal, slippage);
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertGt(vPool.balanceOf(address(owner3)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapInWithVolatilePoolAndETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPoolPreBal = USDC.balanceOf(address(vPool));
        uint256 wethPoolPreBal = WETH.balanceOf(address(vPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPool.balanceOf(address(owner2)), 0);

        uint256 zapAmount = TOKEN_1 * 5;
        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(WETH), address(USDC), false, address(factory));
        IRouter.Zap memory zapInPool = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(factory),
            zapAmount / 2,
            zapAmount / 2,
            routesA,
            routesB
        );

        _router.zapIn{value: zapAmount}(
            ETHER,
            zapAmount / 2,
            zapAmount / 2,
            zapInPool,
            routesA,
            routesB,
            address(owner2),
            false
        );

        uint256 fee = ((zapAmount / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((zapAmount / 2 / 1e12) * ETH_PRICE * vSLIPPAGE) / MAX_BPS;

        assertEq(WETH.balanceOf(address(vPool)) - wethPoolPreBal, 5 * TOKEN_1 - fee);
        assertLt(usdcPoolPreBal - USDC.balanceOf(address(vPool)), slippage);
        assertLt(USDC.balanceOf(address(owner2)) - usdcOwnerPreBal, slippage);
        assertEq(ethOwnerPreBal - address(owner2).balance, 5 * TOKEN_1);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal);
        assertGt(vPool.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapAndStakeWithVolatilePool() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPoolPreBal = USDC.balanceOf(address(vPool));
        uint256 wethPoolPreBal = WETH.balanceOf(address(vPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertEq(vPool.balanceOf(address(vGauge)), 0);
        assertEq(vGauge.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(factory));
        IRouter.Route[] memory routesB = new IRouter.Route[](0);
        IRouter.Zap memory zapInPool = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(factory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zapInPool, routesA, routesB, address(owner2), true);

        uint256 fee = ((USDC_10K / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertEq(USDC.balanceOf(address(vPool)) - usdcPoolPreBal, USDC_10K - fee);
        assertEq(usdcOwnerPreBal - USDC.balanceOf(address(owner2)), USDC_10K);
        assertLt(wethPoolPreBal - WETH.balanceOf(address(vPool)), slippage);
        assertEq(address(owner2).balance, ethOwnerPreBal);
        assertLt(WETH.balanceOf(address(owner2)) - wethOwnerPreBal, slippage);
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertGt(vPool.balanceOf(address(vGauge)), 0);
        assertGt(vGauge.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        assertEq(vPool.allowance(address(_router), address(vGauge)), 0);
        vm.stopPrank();
    }

    function testZapAndStakeWithVolatilePoolAndETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);

        uint256 usdcPoolPreBal = USDC.balanceOf(address(vPool));
        uint256 wethPoolPreBal = WETH.balanceOf(address(vPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertEq(vPool.balanceOf(address(vGauge)), 0);
        assertEq(vGauge.balanceOf(address(owner2)), 0);

        uint256 zapAmount = TOKEN_1 * 5;
        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(WETH), address(USDC), false, address(factory));
        IRouter.Zap memory zapInPool = _createZapInParams(
            address(WETH),
            address(USDC),
            false,
            address(factory),
            zapAmount / 2,
            zapAmount / 2,
            routesA,
            routesB
        );

        _router.zapIn{value: zapAmount}(
            ETHER,
            zapAmount / 2,
            zapAmount / 2,
            zapInPool,
            routesA,
            routesB,
            address(owner2),
            true
        );

        uint256 fee = ((zapAmount / 2) * feeRate) / MAX_BPS;
        uint256 slippage = ((zapAmount / 2 / 1e12) * ETH_PRICE * vSLIPPAGE) / MAX_BPS;

        assertEq(WETH.balanceOf(address(vPool)) - wethPoolPreBal, 5 * TOKEN_1 - fee);
        assertLt(usdcPoolPreBal - USDC.balanceOf(address(vPool)), slippage);
        assertLt(USDC.balanceOf(address(owner2)) - usdcOwnerPreBal, slippage);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal);
        assertEq(ethOwnerPreBal - address(owner2).balance, 5 * TOKEN_1);
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertGt(vPool.balanceOf(address(vGauge)), 0);
        assertGt(vGauge.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        assertEq(vPool.allowance(address(_router), address(vGauge)), 0);
        vm.stopPrank();
    }

    function testZapOutWithVolatilePoolWithTokenInPool() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);
        assertEq(vPool.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(USDC), address(WETH), false, address(factory));
        IRouter.Zap memory zap = _createZapInParams(
            address(USDC),
            address(WETH),
            false,
            address(factory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zap, routesA, routesB, address(owner2), false);
        uint256 liquidity = vPool.balanceOf(address(owner2));
        assertGt(liquidity, 0);

        uint256 amount = vPool.balanceOf(address(owner2));
        uint256 usdcPoolPreBal = USDC.balanceOf(address(vPool));
        uint256 wethPoolPreBal = WETH.balanceOf(address(vPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;

        routesB[0] = IRouter.Route(address(WETH), address(USDC), false, address(factory));
        zap = _createZapOutParams(address(USDC), address(WETH), false, address(factory), liquidity, routesA, routesB);
        vPool.approve(address(_router), type(uint256).max);
        _router.zapOut(address(USDC), amount, zap, routesA, routesB);

        uint256 slippage = ((USDC_10K / 2) * vSLIPPAGE) / MAX_BPS;

        // experience slippage twice as we zap in and out
        assertEq(address(owner2).balance, ethOwnerPreBal);
        assertGt(USDC.balanceOf(address(owner2)) - usdcOwnerPreBal, USDC_10K - 2 * slippage);
        assertGt(usdcPoolPreBal - USDC.balanceOf(address(vPool)), USDC_10K - 2 * slippage);
        assertLt(wethPoolPreBal - WETH.balanceOf(address(vPool)), TOKEN_1 / 100);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal);
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapOutWithVolatilePoolWithTokenInPoolWithETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);
        assertEq(vPool.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(USDC), address(WETH), false, address(factory));
        IRouter.Zap memory zap = _createZapInParams(
            address(USDC),
            address(WETH),
            false,
            address(factory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zap, routesA, routesB, address(owner2), false);

        uint256 liquidity = vPool.balanceOf(address(owner2));
        assertGt(liquidity, 0);

        uint256 usdcPoolPreBal = USDC.balanceOf(address(vPool));
        uint256 wethPoolPreBal = WETH.balanceOf(address(vPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        // approximate return value
        uint256 expectedETH = vPool.getAmountOut(USDC_10K, address(USDC));

        delete routesB[0];
        routesA = new IRouter.Route[](1);
        routesB = new IRouter.Route[](0);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(factory));
        zap = _createZapOutParams(address(USDC), address(WETH), false, address(factory), liquidity, routesA, routesB);

        // request WETH
        vPool.approve(address(_router), type(uint256).max);
        _router.zapOut(ETHER, liquidity, zap, routesA, routesB);

        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertGt(address(owner2).balance - ethOwnerPreBal, expectedETH - 2 * slippage);
        assertEq(USDC.balanceOf(address(owner2)), usdcOwnerPreBal);
        assertLt(usdcPoolPreBal - USDC.balanceOf(address(vPool)), 15 * USDC_1);
        assertApproxEqRel(wethPoolPreBal - WETH.balanceOf(address(vPool)), expectedETH, 1e16);
        assertEq(WETH.balanceOf(address(owner2)), wethOwnerPreBal); // no change in WETH balance
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function testZapOutWithVolatilePoolWithTokenInPoolWithWETH() public {
        vm.startPrank(address(owner2));
        USDC.approve(address(_router), type(uint256).max);
        assertEq(vPool.balanceOf(address(owner2)), 0);

        IRouter.Route[] memory routesA = new IRouter.Route[](0);
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(USDC), address(WETH), false, address(factory));
        IRouter.Zap memory zap = _createZapInParams(
            address(USDC),
            address(WETH),
            false,
            address(factory),
            USDC_10K / 2,
            USDC_10K / 2,
            routesA,
            routesB
        );

        _router.zapIn(address(USDC), USDC_10K / 2, USDC_10K / 2, zap, routesA, routesB, address(owner2), false);
        uint256 liquidity = vPool.balanceOf(address(owner2));
        assertGt(liquidity, 0);

        uint256 usdcPoolPreBal = USDC.balanceOf(address(vPool));
        uint256 wethPoolPreBal = WETH.balanceOf(address(vPool));
        uint256 usdcOwnerPreBal = USDC.balanceOf(address(owner2));
        uint256 wethOwnerPreBal = WETH.balanceOf(address(owner2));
        uint256 ethOwnerPreBal = address(owner2).balance;
        // approximate return value
        uint256 expectedETH = vPool.getAmountOut(USDC_10K, address(USDC));

        delete routesB;
        routesA = new IRouter.Route[](1);
        routesB = new IRouter.Route[](0);
        routesA[0] = IRouter.Route(address(USDC), address(WETH), false, address(factory));
        zap = _createZapOutParams(address(USDC), address(WETH), false, address(factory), liquidity, routesA, routesB);

        // request WETH
        vPool.approve(address(_router), type(uint256).max);
        _router.zapOut(address(WETH), liquidity, zap, routesA, routesB);

        uint256 slippage = ((((USDC_10K / 2) * 1e12) / ETH_PRICE) * vSLIPPAGE) / MAX_BPS;

        assertGt(WETH.balanceOf(address(owner2)) - wethOwnerPreBal, expectedETH - 2 * slippage);
        assertEq(USDC.balanceOf(address(owner2)), usdcOwnerPreBal);
        assertLt(usdcPoolPreBal - USDC.balanceOf(address(vPool)), 15 * USDC_1);
        assertApproxEqRel(wethPoolPreBal - WETH.balanceOf(address(vPool)), expectedETH, 1e16);
        assertEq(address(owner2).balance, ethOwnerPreBal); // no change in ETH balance
        assertEq(vPool.balanceOf(address(owner2)), 0);
        assertEq(USDC.balanceOf(address(_router)), 0);
        assertEq(WETH.balanceOf(address(_router)), 0);
        vm.stopPrank();
    }

    function _createZapInParams(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountInA,
        uint256 amountInB,
        IRouter.Route[] memory routesA,
        IRouter.Route[] memory routesB
    ) internal view returns (IRouter.Zap memory zap) {
        // use 300 bps slippage for the smaller stable pool
        uint256 slippage = (stable == true) ? 300 : 50;
        (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) = _router
            .generateZapInParams(tokenA, tokenB, stable, _factory, amountInA, amountInB, routesA, routesB);

        amountAMin = (amountAMin * (MAX_BPS - slippage)) / MAX_BPS;
        amountBMin = (amountBMin * (MAX_BPS - slippage)) / MAX_BPS;
        return IRouter.Zap(tokenA, tokenB, stable, _factory, amountOutMinA, amountOutMinB, amountAMin, amountBMin);
    }

    function _createZapOutParams(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 liquidity,
        IRouter.Route[] memory routesA,
        IRouter.Route[] memory routesB
    ) internal view returns (IRouter.Zap memory zap) {
        // use 300 bps slippage for the smaller stable pool
        uint256 slippage = (stable == true) ? 300 : 50;
        (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) = _router
            .generateZapOutParams(tokenA, tokenB, stable, _factory, liquidity, routesA, routesB);
        amountOutMinA = (amountOutMinA * (MAX_BPS - slippage)) / MAX_BPS;
        amountOutMinB = (amountOutMinB * (MAX_BPS - slippage)) / MAX_BPS;
        return IRouter.Zap(tokenA, tokenB, stable, _factory, amountOutMinA, amountOutMinB, amountAMin, amountBMin);
    }
}
