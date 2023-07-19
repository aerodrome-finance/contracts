// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract WashTradeTest is BaseTest {
    constructor() {
        deploymentType = Deployment.CUSTOM;
    }

    function deployBaseCoins() public {
        skip(1 weeks);

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
        vm.roll(block.number + 1); // fwd 1 block because escrow.balanceOfNFT() returns 0 in same block
        assertGt(escrow.balanceOfNFT(1), 995063075414519385);
        assertEq(VELO.balanceOf(address(escrow)), TOKEN_1);
    }

    function votingEscrowMerge() public {
        createLock();

        VELO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1);
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
        voter.createGauge(address(factory), address(pool2));
        voter.createGauge(address(factory), address(pool3));
        assertFalse(voter.gauges(address(pool3)) == address(0));

        address gaugeAddr3 = voter.gauges(address(pool3));
        address feesVotingRewardAddr3 = voter.gaugeToFees(gaugeAddr3);

        gauge3 = Gauge(gaugeAddr3);

        feesVotingReward3 = FeesVotingReward(feesVotingRewardAddr3);
        uint256 total = pool3.balanceOf(address(owner));
        pool3.approve(address(gauge3), total);
        gauge3.deposit(total);
        assertEq(gauge3.totalSupply(), total);
        assertEq(gauge3.earned(address(owner)), 0);
    }

    function routerPool3GetAmountsOutAndSwapExactTokensForTokens() public {
        deployPoolFactoryGauge();

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route(address(FRAX), address(DAI), true, address(0));
        IRouter.Route[] memory routes2 = new IRouter.Route[](1);
        routes2[0] = IRouter.Route(address(DAI), address(FRAX), true, address(0));

        uint256 i;
        for (i = 0; i < 10; i++) {
            assertEq(router.getAmountsOut(TOKEN_1M, routes)[1], pool3.getAmountOut(TOKEN_1M, address(FRAX)));

            uint256[] memory expectedOutput = router.getAmountsOut(TOKEN_1M, routes);
            FRAX.approve(address(router), TOKEN_1M);
            router.swapExactTokensForTokens(TOKEN_1M, expectedOutput[1], routes, address(owner), block.timestamp);

            assertEq(router.getAmountsOut(TOKEN_1M, routes2)[1], pool3.getAmountOut(TOKEN_1M, address(DAI)));

            uint256[] memory expectedOutput2 = router.getAmountsOut(TOKEN_1M, routes2);
            DAI.approve(address(router), TOKEN_1M);
            router.swapExactTokensForTokens(TOKEN_1M, expectedOutput2[1], routes2, address(owner), block.timestamp);
        }
    }

    function voterReset() public {
        routerPool3GetAmountsOutAndSwapExactTokensForTokens();

        distributor = new RewardsDistributor(address(escrow));
        escrow.setVoterAndDistributor(address(voter), address(distributor));
        skip(1 hours);
        voter.reset(1);
    }

    function voterPokeSelf() public {
        voterReset();

        voter.poke(1);
    }

    function voterVoteAndFeesVotingRewardBalanceOf() public {
        voterPokeSelf();

        skipToNextEpoch(1 hours + 1);

        address[] memory pools = new address[](2);
        pools[0] = address(pool3);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 5000;
        voter.vote(1, pools, weights);
        assertFalse(voter.totalWeight() == 0);
        assertFalse(feesVotingReward3.balanceOf(1) == 0);
    }

    function feesVotingRewardClaimRewards() public {
        voterVoteAndFeesVotingRewardBalanceOf();

        address[] memory tokens = new address[](2);
        tokens[0] = address(FRAX);
        tokens[1] = address(DAI);
        feesVotingReward3.getReward(1, tokens);
        skip(8 days);
        vm.roll(block.number + 1);
        feesVotingReward3.getReward(1, tokens);
    }

    function distributeAndClaimFees() public {
        feesVotingRewardClaimRewards();

        skip(8 days);
        vm.roll(block.number + 1);
        address[] memory tokens = new address[](2);
        tokens[0] = address(FRAX);
        tokens[1] = address(DAI);
        feesVotingReward3.getReward(1, tokens);

        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge3);
    }

    function testBribeClaimRewards() public {
        distributeAndClaimFees();

        console2.log(feesVotingReward3.earned(address(FRAX), 1));
        console2.log(FRAX.balanceOf(address(owner)));
        console2.log(FRAX.balanceOf(address(feesVotingReward3)));
        address[] memory tokens = new address[](2);
        tokens[0] = address(FRAX);
        tokens[1] = address(DAI);
        feesVotingReward3.getReward(1, tokens);
        skip(8 days);
        vm.roll(block.number + 1);
        console2.log(feesVotingReward3.earned(address(FRAX), 1));
        console2.log(FRAX.balanceOf(address(owner)));
        console2.log(FRAX.balanceOf(address(feesVotingReward3)));
        feesVotingReward3.getReward(1, tokens);
        console2.log(feesVotingReward3.earned(address(FRAX), 1));
        console2.log(FRAX.balanceOf(address(owner)));
        console2.log(FRAX.balanceOf(address(feesVotingReward3)));
    }
}
