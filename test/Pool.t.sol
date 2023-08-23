// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract PoolTest is BaseTest {
    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function deployPoolCoins() public {
        skip(1 weeks);

        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2e25;
        amounts[1] = 1e25;
        amounts[2] = 1e25;
        mintToken(address(AERO), owners, amounts);
        mintToken(address(LR), owners, amounts);
        deployFactories();
        factory.setFee(true, 1);
        factory.setFee(false, 1);

        escrow = new VotingEscrow(address(forwarder), address(AERO), address(factoryRegistry));
        VeArtProxy artProxy = new VeArtProxy(address(escrow));
        escrow.setArtProxy(address(artProxy));

        distributor = new RewardsDistributor(address(escrow));
        voter = new Voter(address(forwarder), address(escrow), address(factoryRegistry));
        router = new Router(
            address(forwarder),
            address(factoryRegistry),
            address(factory),
            address(voter),
            address(WETH)
        );

        escrow.setVoterAndDistributor(address(voter), address(distributor));
        factory.setVoter(address(voter));

        deployPoolWithOwner(address(owner));
        deployPoolWithOwner(address(owner2));
    }

    function createLock() public {
        deployPoolCoins();

        AERO.approve(address(escrow), 5e17);
        escrow.createLock(5e17, MAXTIME);
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 495063075414519385);
        assertEq(AERO.balanceOf(address(escrow)), 5e17);
    }

    function increaseLock() public {
        createLock();

        AERO.approve(address(escrow), 5e17);
        escrow.increaseAmount(1, 5e17);
        vm.expectRevert(IVotingEscrow.LockDurationNotInFuture.selector);
        escrow.increaseUnlockTime(1, MAXTIME);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(AERO.balanceOf(address(escrow)), TOKEN_1);
    }

    function votingEscrowViews() public {
        increaseLock();

        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(AERO.balanceOf(address(escrow)), TOKEN_1);
    }

    function stealNFT() public {
        votingEscrowViews();

        vm.startPrank(address(owner2));
        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        escrow.transferFrom(address(owner), address(owner2), 1);
        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        escrow.approve(address(owner2), 1);
        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        escrow.merge(1, 2);
        vm.stopPrank();
    }

    function votingEscrowMerge() public {
        stealNFT();

        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        assertGt(escrow.balanceOfNFT(2), 995063075414519385);
        assertEq(AERO.balanceOf(address(escrow)), 2 * TOKEN_1);

        escrow.merge(2, 1);
        assertGt(escrow.balanceOfNFT(1), 1990063075414519385);
        assertEq(escrow.balanceOfNFT(2), 0);

        IVotingEscrow.LockedBalance memory locked;

        locked = escrow.locked(2);
        assertEq(locked.amount, 0);
        assertEq(escrow.ownerOf(2), address(0));

        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        assertGt(escrow.balanceOfNFT(3), 995063075414519385);
        assertEq(AERO.balanceOf(address(escrow)), 3 * TOKEN_1);

        escrow.merge(3, 1);
        assertGt(escrow.balanceOfNFT(1), 1990063075414519385);
        assertEq(escrow.balanceOfNFT(3), 0);

        locked = escrow.locked(3);
        assertEq(locked.amount, 0);
        assertEq(escrow.ownerOf(3), address(0));
    }

    function confirmTokensForFraxUsdc() public {
        votingEscrowMerge();

        (address token0, address token1) = router.sortTokens(address(USDC), address(FRAX));
        assertEq(pool.token0(), token0);
        assertEq(pool.token1(), token1);
    }

    function mintAndBurnTokensForPoolFraxUsdc() public {
        confirmTokensForFraxUsdc();

        USDC.transfer(address(pool), USDC_1);
        FRAX.transfer(address(pool), TOKEN_1);
        pool.mint(address(owner));
        assertEq(pool.getAmountOut(USDC_1, address(USDC)), 982117769725505988);
    }

    function mintAndBurnTokensForPoolFraxUsdcOwner2() public {
        mintAndBurnTokensForPoolFraxUsdc();

        vm.startPrank(address(owner2));
        USDC.transfer(address(pool), USDC_1);
        FRAX.transfer(address(pool), TOKEN_1);
        pool.mint(address(owner2));
        vm.stopPrank();

        assertEq(pool.getAmountOut(USDC_1, address(USDC)), 992220948146798746);
    }

    function routerAddLiquidity() public {
        mintAndBurnTokensForPoolFraxUsdcOwner2();

        _addLiquidityToPool(address(owner), address(router), address(USDC), address(FRAX), true, USDC_100K, TOKEN_100K);
        _addLiquidityToPool(
            address(owner),
            address(router),
            address(USDC),
            address(FRAX),
            false,
            USDC_100K,
            TOKEN_100K
        );
        _addLiquidityToPool(address(owner), address(router), address(DAI), address(FRAX), true, TOKEN_100M, TOKEN_100M);
    }

    function routerRemoveLiquidity() public {
        routerAddLiquidity();

        USDC.approve(address(router), USDC_100K);
        FRAX.approve(address(router), TOKEN_100K);
        router.quoteAddLiquidity(address(FRAX), address(USDC), true, address(factory), TOKEN_100K, USDC_100K);
        router.quoteRemoveLiquidity(address(FRAX), address(USDC), true, address(factory), USDC_100K);
    }

    function routerAddLiquidityOwner2() public {
        routerRemoveLiquidity();

        _addLiquidityToPool(
            address(owner2),
            address(router),
            address(USDC),
            address(FRAX),
            true,
            USDC_100K,
            TOKEN_100K
        );
        _addLiquidityToPool(
            address(owner2),
            address(router),
            address(USDC),
            address(FRAX),
            false,
            USDC_100K,
            TOKEN_100K
        );
        _addLiquidityToPool(
            address(owner2),
            address(router),
            address(DAI),
            address(FRAX),
            true,
            TOKEN_100M,
            TOKEN_100M
        );
    }

    function routerPool1GetAmountsOutAndSwapExactTokensForTokens() public {
        routerAddLiquidityOwner2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pool.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory assertedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, assertedOutput[1], routes, address(owner), block.timestamp);
        skip(1801);
        vm.roll(block.number + 1);
        address poolFees = pool.poolFees();
        assertEq(USDC.balanceOf(poolFees), 100);
        uint256 b = USDC.balanceOf(address(owner));
        pool.claimFees();
        assertGt(USDC.balanceOf(address(owner)), b);
    }

    function routerPool1GetAmountsOutAndSwapExactTokensForTokensOwner2() public {
        routerPool1GetAmountsOutAndSwapExactTokensForTokens();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pool.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        vm.startPrank(address(owner2));
        owner2.approve(address(USDC), address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner2), block.timestamp);
        vm.stopPrank();
        address poolFees = pool.poolFees();
        assertEq(USDC.balanceOf(poolFees), 101);
        uint256 b = USDC.balanceOf(address(owner));
        vm.prank(address(owner2));
        pool.claimFees();
        assertEq(USDC.balanceOf(address(owner)), b);
    }

    function routerPool2GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPool1GetAmountsOutAndSwapExactTokensForTokensOwner2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), false, address(0));

        assertEq(router.getAmountsOut(USDC_1, routes)[1], pool2.getAmountOut(USDC_1, address(USDC)));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPool3GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPool2GetAmountsOutAndSwapExactTokensForTokens();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(DAI), true, address(0));

        assertEq(router.getAmountsOut(TOKEN_1M, routes)[1], pool3.getAmountOut(TOKEN_1M, address(FRAX)));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1M, routes);
        FRAX.approve(address(router), TOKEN_1M);
        router.swapExactTokensForTokens(TOKEN_1M, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function deployMinter() public {
        routerAddLiquidity();

        distributor = new RewardsDistributor(address(escrow));

        minter = new Minter(address(voter), address(escrow), address(distributor));
        distributor.setMinter(address(minter));
        AERO.setMinter(address(minter));
        address[] memory tokens = new address[](5);
        tokens[0] = address(USDC);
        tokens[1] = address(FRAX);
        tokens[2] = address(DAI);
        tokens[3] = address(AERO);
        tokens[4] = address(LR);
        voter.initialize(tokens, address(minter));
    }

    function deployPoolFactoryGauge() public {
        deployMinter();

        AERO.approve(address(gaugeFactory), 15 * TOKEN_100K);
        voter.createGauge(address(factory), address(pool));
        voter.createGauge(address(factory), address(pool2));
        voter.createGauge(address(factory), address(pool3));
        assertFalse(voter.gauges(address(pool)) == address(0));

        address gaugeAddress = voter.gauges(address(pool));
        address feesVotingRewardAddress = voter.gaugeToFees(gaugeAddress);
        address bribeVotingRewardAddress = voter.gaugeToBribe(gaugeAddress);

        address gaugeAddress2 = voter.gauges(address(pool2));
        address feesVotingRewardAddress2 = voter.gaugeToFees(gaugeAddress2);

        address gaugeAddress3 = voter.gauges(address(pool3));
        address feesVotingRewardAddress3 = voter.gaugeToFees(gaugeAddress3);

        gauge = Gauge(gaugeAddress);
        gauge2 = Gauge(gaugeAddress2);
        gauge3 = Gauge(gaugeAddress3);

        feesVotingReward = FeesVotingReward(feesVotingRewardAddress);
        bribeVotingReward = BribeVotingReward(bribeVotingRewardAddress);
        feesVotingReward2 = FeesVotingReward(feesVotingRewardAddress2);
        feesVotingReward3 = FeesVotingReward(feesVotingRewardAddress3);

        pool.approve(address(gauge), POOL_1);
        pool2.approve(address(gauge2), POOL_1);
        pool3.approve(address(gauge3), POOL_1);
        gauge.deposit(POOL_1);
        gauge2.deposit(POOL_1);
        gauge3.deposit(POOL_1);
        assertEq(gauge.totalSupply(), POOL_1);
        assertEq(gauge.earned(address(owner)), 0);
    }

    function deployPoolFactoryGaugeOwner2() public {
        deployPoolFactoryGauge();

        owner2.approve(address(pool), address(gauge), POOL_1);
        owner2.deposit(address(gauge), POOL_1);
        assertEq(gauge.totalSupply(), 2 * POOL_1);
        assertEq(gauge.earned(address(owner2)), 0);
    }

    function withdrawGaugeStake() public {
        deployPoolFactoryGaugeOwner2();

        gauge.withdraw(gauge.balanceOf(address(owner)));
        owner2.withdrawGauge(address(gauge), gauge.balanceOf(address(owner2)));
        gauge2.withdraw(gauge2.balanceOf(address(owner)));
        gauge3.withdraw(gauge3.balanceOf(address(owner)));
        assertEq(gauge.totalSupply(), 0);
        assertEq(gauge2.totalSupply(), 0);
        assertEq(gauge3.totalSupply(), 0);
    }

    function addGaugeAndVotingRewards() public {
        withdrawGaugeStake();

        _addRewardToGauge(address(voter), address(gauge), POOL_1);

        AERO.approve(address(bribeVotingReward), POOL_1);

        bribeVotingReward.notifyRewardAmount(address(AERO), POOL_1);

        assertEq(gauge.rewardRate(), 1653);
    }

    function exitAndGetRewardGaugeStake() public {
        addGaugeAndVotingRewards();

        uint256 supply = pool.balanceOf(address(owner));
        pool.approve(address(gauge), supply);
        gauge.deposit(supply);
        gauge.withdraw(gauge.balanceOf(address(owner)));
        assertEq(gauge.totalSupply(), 0);
        pool.approve(address(gauge), supply);
        gauge.deposit(POOL_1);
    }

    function voterReset() public {
        exitAndGetRewardGaugeStake();

        skip(1 weeks + 1 hours + 1);
        voter.reset(1);
    }

    function voterPokeSelf() public {
        voterReset();

        voter.poke(1);
    }

    function createLock2() public {
        voterPokeSelf();

        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(AERO.balanceOf(address(escrow)), 4 * TOKEN_1);
    }

    function voteHacking() public {
        createLock2();

        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        skip(1 weeks + 1 hours + 1);

        voter.vote(1, pools, weights);
        assertEq(voter.usedWeights(1), escrow.balanceOfNFT(1)); // within 1000
        assertEq(feesVotingReward.balanceOf(1), uint256(voter.votes(1, address(pool))));
        skip(1 weeks);

        voter.reset(1);
        assertLt(voter.usedWeights(1), escrow.balanceOfNFT(1));
        assertEq(voter.usedWeights(1), 0);
        assertEq(feesVotingReward.balanceOf(1), uint256(voter.votes(1, address(pool))));
        assertEq(feesVotingReward.balanceOf(1), 0);
    }

    function gaugePokeHacking() public {
        voteHacking();

        assertEq(voter.usedWeights(1), 0);
        assertEq(voter.votes(1, address(pool)), 0);
        voter.poke(1);
        assertEq(voter.usedWeights(1), 0);
        assertEq(voter.votes(1, address(pool)), 0);
    }

    function gaugeVoteAndBribeBalanceOf() public {
        gaugePokeHacking();

        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        skip(1 weeks + 1 hours + 1);

        voter.vote(1, pools, weights);
        weights[0] = 50000;
        weights[1] = 50000;

        voter.vote(4, pools, weights);
        assertFalse(voter.totalWeight() == 0);
        assertFalse(feesVotingReward.balanceOf(1) == 0);
    }

    function gaugePokeHacking2() public {
        gaugeVoteAndBribeBalanceOf();

        uint256 weightBefore = voter.usedWeights(1);
        uint256 votesBefore = voter.votes(1, address(pool));
        voter.poke(1);
        assertEq(voter.usedWeights(1), weightBefore);
        assertEq(voter.votes(1, address(pool)), votesBefore);
    }

    function voteHackingBreakMint() public {
        gaugePokeHacking2();

        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5000;
        skip(1 weeks);

        voter.vote(1, pools, weights);

        assertEq(voter.usedWeights(1), escrow.balanceOfNFT(1)); // within 1000
        assertEq(feesVotingReward.balanceOf(1), uint256(voter.votes(1, address(pool))));
    }

    function gaugePokeHacking3() public {
        voteHackingBreakMint();

        assertEq(voter.usedWeights(1), uint256(voter.votes(1, address(pool))));
        voter.poke(1);
        assertEq(voter.usedWeights(1), uint256(voter.votes(1, address(pool))));
    }

    function gaugeDistributeBasedOnVoting() public {
        gaugePokeHacking3();

        deal(address(AERO), address(minter), POOL_1);

        vm.startPrank(address(minter));
        AERO.approve(address(voter), POOL_1);
        voter.notifyRewardAmount(POOL_1);
        vm.stopPrank();

        voter.updateFor(0, voter.length());
        voter.distribute(0, voter.length());
    }

    function feesVotingRewardClaimRewards() public {
        gaugeDistributeBasedOnVoting();

        address[] memory rewards = new address[](1);
        rewards[0] = address(AERO);
        feesVotingReward.getReward(1, rewards);
        skip(8 days);
        vm.roll(block.number + 1);
        feesVotingReward.getReward(1, rewards);
    }

    function routerPool1GetAmountsOutAndSwapExactTokensForTokens2() public {
        feesVotingRewardClaimRewards();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPool2GetAmountsOutAndSwapExactTokensForTokens2() public {
        routerPool1GetAmountsOutAndSwapExactTokensForTokens2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(USDC), address(FRAX), false, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(USDC_1, routes);
        USDC.approve(address(router), USDC_1);
        router.swapExactTokensForTokens(USDC_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPool1GetAmountsOutAndSwapExactTokensForTokens2Again() public {
        routerPool2GetAmountsOutAndSwapExactTokensForTokens2();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, routes);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPool2GetAmountsOutAndSwapExactTokensForTokens2Again() public {
        routerPool1GetAmountsOutAndSwapExactTokensForTokens2Again();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, routes);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[1], routes, address(owner), block.timestamp);
    }

    function routerPool1Pool2GetAmountsOutAndSwapExactTokensForTokens() public {
        routerPool2GetAmountsOutAndSwapExactTokensForTokens2Again();

        IRouter.Route[] memory route = new IRouter.Route[](2);
        route[0] = IRouter.Route(address(FRAX), address(USDC), false, address(0));
        route[1] = IRouter.Route(address(USDC), address(FRAX), true, address(0));

        uint256 before = FRAX.balanceOf(address(owner)) - TOKEN_1;

        uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1, route);
        FRAX.approve(address(router), TOKEN_1);
        router.swapExactTokensForTokens(TOKEN_1, expectedOutput[2], route, address(owner), block.timestamp);
        uint256 after_ = FRAX.balanceOf(address(owner));
        assertEq(after_ - before, expectedOutput[2]);
    }

    function distributeAndClaimFees() public {
        routerPool1Pool2GetAmountsOutAndSwapExactTokensForTokens();

        skip(8 days);
        vm.roll(block.number + 1);
        address[] memory rewards = new address[](2);
        rewards[0] = address(FRAX);
        rewards[1] = address(USDC);
        feesVotingReward.getReward(1, rewards);

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
    }

    function minterMint() public {
        distributeAndClaimFees();

        minter.updatePeriod();
        voter.updateFor(address(gauge));
        voter.distribute(0, voter.length());
        skip(30 minutes);
        vm.roll(block.number + 1);
    }

    function gaugeClaimRewards() public {
        minterMint();

        assertEq(address(owner), escrow.ownerOf(1));
        assertTrue(escrow.isApprovedOrOwner(address(owner), 1));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        skip(1);
        pool.approve(address(gauge), POOL_1);
        skip(1);
        gauge.deposit(POOL_1);
        skip(1);
        uint256 before = AERO.balanceOf(address(owner));
        skip(1);
        uint256 earned = gauge.earned(address(owner));
        gauge.getReward(address(owner));
        skip(1);
        uint256 after_ = AERO.balanceOf(address(owner));
        uint256 received = after_ - before;
        assertEq(earned, received);

        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        skip(1 weeks);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function gaugeClaimRewardsAfterExpiry() public {
        gaugeClaimRewards();

        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);
        gauge.getReward(address(owner));
        skip(1 weeks);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function votingEscrowDecay() public {
        gaugeClaimRewardsAfterExpiry();

        address[] memory feesVotingRewards_ = new address[](1);
        feesVotingRewards_[0] = address(feesVotingReward);
        address[][] memory rewards = new address[][](1);
        address[] memory reward = new address[](1);
        reward[0] = address(DAI);
        rewards[0] = reward;
        voter.claimBribes(feesVotingRewards_, rewards, 1);
        voter.claimFees(feesVotingRewards_, rewards, 1);
        uint256 supply = escrow.totalSupply();
        assertGt(supply, 0);
        skip(MAXTIME);
        vm.roll(block.number + 1);
        assertEq(escrow.balanceOfNFT(1), 0);
        assertEq(escrow.totalSupply(), 0);
        skip(1 weeks);

        voter.reset(1);
        escrow.withdraw(1);
    }

    function routerAddLiquidityOwner3() public {
        votingEscrowDecay();

        _addLiquidityToPool(address(owner3), address(router), address(USDC), address(FRAX), true, 1e12, TOKEN_1M);
    }

    function deployPoolFactoryGaugeOwner3() public {
        routerAddLiquidityOwner3();

        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);
    }

    function gaugeClaimRewardsOwner3() public {
        deployPoolFactoryGaugeOwner3();

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);

        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.getGaugeReward(address(gauge), address(owner3));
        owner3.getGaugeReward(address(gauge), address(owner3));

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner)));
        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
    }

    function minterMint2() public {
        gaugeClaimRewardsOwner3();

        skip(2 weeks);
        vm.roll(block.number + 1);
        minter.updatePeriod();
        voter.updateFor(address(gauge));
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        voter.updateFor(gauges);
        voter.distribute(0, voter.length());
        voter.claimRewards(gauges);
        assertEq(gauge.rewardRate(), 71886434476216289470);
        console2.log(gauge.rewardPerTokenStored());
    }

    function gaugeClaimRewardsOwner3NextCycle() public {
        minterMint2();

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner3)));
        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);
        uint256 before = AERO.balanceOf(address(owner3));
        skip(1);
        owner3.getGaugeReward(address(gauge), address(owner3));
        uint256 after_ = AERO.balanceOf(address(owner3));
        uint256 received = after_ - before;
        assertGt(received, 0);

        owner3.withdrawGauge(address(gauge), gauge.balanceOf(address(owner)));
        owner3.approve(address(pool), address(gauge), POOL_1);
        owner3.deposit(address(gauge), POOL_1);
        owner3.getGaugeReward(address(gauge), address(owner3));
    }

    function testGaugeClaimRewards2() public {
        gaugeClaimRewardsOwner3NextCycle();

        pool.approve(address(gauge), POOL_1);
        gauge.deposit(POOL_1);

        _addRewardToGauge(address(voter), address(gauge), TOKEN_1);

        skip(1 weeks);
        vm.roll(block.number + 1);
        gauge.getReward(address(owner));
        gauge.withdraw(gauge.balanceOf(address(owner)));
    }

    function testSetPoolName() external {
        // Note: as this contract is a custom setup, the pool contracts are not already deployed from
        // base setup, and so they need to be deployed for these tests
        deployPoolCoins();

        assertEq(pool.name(), "Stable AMM - USDC/FRAX");
        pool.setName("Some new name");
        assertEq(pool.name(), "Some new name");
    }

    function testCannotSetPoolNameIfNotEmergencyCouncil() external {
        deployPoolCoins();

        vm.prank(address(owner2));
        vm.expectRevert(IPool.NotEmergencyCouncil.selector);
        pool.setName("Some new name");
    }

    function testSetPoolSymbol() external {
        deployPoolCoins();

        assertEq(pool.symbol(), "sAMM-USDC/FRAX");
        pool.setSymbol("Some new symbol");
        assertEq(pool.symbol(), "Some new symbol");
    }

    function testCannotSetPoolSymbolIfNotEmergencyCouncil() external {
        deployPoolCoins();

        vm.prank(address(owner2));
        vm.expectRevert(IPool.NotEmergencyCouncil.selector);
        pool.setSymbol("Some new symbol");
    }
}
