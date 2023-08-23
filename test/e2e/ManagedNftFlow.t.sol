// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./ExtendedBaseTest.sol";

contract ManagedNftFlow is ExtendedBaseTest {
    LockedManagedReward lockedManagedReward;
    FreeManagedReward freeManagedReward;

    uint256 tokenId;
    uint256 tokenId2;
    uint256 tokenId3;

    function _setUp() public override {
        AERO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAX_TIME);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        tokenId2 = escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();
        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_1);
        tokenId3 = escrow.createLock(TOKEN_1, MAX_TIME);
        vm.stopPrank();
        skip(1);
    }

    function testSimpleManagedNftFlow() public {
        // owner owns nft with id: tokenId with amount: TOKEN_1
        // owner2 owns nft with id: tokenId2 with amount: TOKEN_1
        // owner3 owns nft with id: tokenId3 with amount: TOKEN_1
        // owner4 owns the managed nft: tokenId4

        // epoch 0:
        // create managed nft
        // deposit into managed nft
        // simulate rebases for epoch 0
        uint256 supply = escrow.supply();

        // switch allowedManager to allow owner4 to create managed lock
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner4));

        vm.prank(address(owner4));
        uint256 mTokenId = escrow.createManagedLockFor(address(owner4));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));

        skip(1 hours);
        voter.depositManaged(tokenId, mTokenId);

        // check deposit successful
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);

        vm.prank(address(owner2));
        voter.depositManaged(tokenId2, mTokenId);

        assertEq(escrow.idToManaged(tokenId2), mTokenId);
        assertEq(escrow.weights(tokenId2, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId2), 0);

        IVotingEscrow.LockedBalance memory locked;
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        // net supply unchanged
        assertEq(escrow.supply(), supply);

        // test voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(AERO);
        rewards[1] = address(USDC);

        // create aero bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(AERO), TOKEN_1 * 2);

        /// total votes:
        /// managed nft: TOKEN_1 * 2
        /// owner3: TOKEN_1 * 2
        vm.prank(address(owner4));
        voter.vote(mTokenId, pools, weights);

        /// owner 3 will vote passively
        vm.prank(address(owner3));
        voter.vote(tokenId3, pools, weights);

        // simulate rebases for epoch 0
        deal(address(AERO), address(distributor), TOKEN_1);
        vm.startPrank(address(distributor));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.depositFor(mTokenId, TOKEN_1);
        vm.stopPrank();
        supply += TOKEN_1;

        assertEq(escrow.supply(), supply);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), TOKEN_1);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), 0);

        // check managed nft token lock increased
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 3);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // must be poked after ve balance change or votes in bribe won't update
        voter.poke(mTokenId);

        skipToNextEpoch(1);

        // check depositor has earned rebases
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), TOKEN_1 / 2);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId2), TOKEN_1 / 2);

        // epoch 1:
        // simulate rebase + non-compounded aero rewards

        /// state of gauge votes:
        /// mTokenId contribution ~= 3 / 4
        /// tokenId3 contribution ~= 1 / 4
        /// mTokenId voting weight = TOKEN_1 * 3 (permanent lock)
        /// tokenId3 voting weight = 997260257999312010 (balance at deposit time)

        // collect rewards from bribe
        uint256 pre = AERO.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        uint256 post = AERO.balanceOf(address(owner4));
        // ~= 3 / 4 go to managed nft. note that managed is perma locked but tokenId3 is not
        assertApproxEqRel(post - pre, ((TOKEN_1 * 2) * 750_514) / 1_000_000, 1e13);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner4));
        AERO.approve(address(freeManagedReward), TOKEN_1 * 2);
        freeManagedReward.notifyRewardAmount(address(AERO), ((TOKEN_1 * 2) * 3) / 4);
        vm.stopPrank();

        // simulate rebases for epoch 1:
        deal(address(AERO), address(distributor), TOKEN_1);
        vm.startPrank(address(distributor));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.depositFor(mTokenId, TOKEN_1);
        vm.stopPrank();
        supply += TOKEN_1;

        assertEq(escrow.supply(), supply);
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 4);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(lockedManagedReward.earned(address(AERO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(AERO), tokenId), 0);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId2), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), 0);

        // create usdc bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(USDC), USDC_1);

        skip(1 hours);
        voter.poke(mTokenId);

        skipToNextEpoch(1);

        assertEq(lockedManagedReward.earned(address(AERO), tokenId), TOKEN_1);
        assertEq(freeManagedReward.earned(address(AERO), tokenId), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId2), TOKEN_1);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), ((TOKEN_1 * 2) * 3) / 4 / 2);

        // epoch 2:
        // simulate rebase + usdc rewards

        /// state of gauge votes:
        /// mTokenId contribution: 4 / 5
        /// tokenId3 contribution: 1 / 5

        uint256 usdcReward = bribeVotingReward.earned(address(USDC), mTokenId);
        pre = USDC.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        post = USDC.balanceOf(address(owner4));
        // allow additional looser error band as USDC is only 6 dec
        assertApproxEqRel(post - pre, (USDC_1 * 4) / 5, 1e15);
        assertEq(post - pre, usdcReward);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner4));
        USDC.approve(address(freeManagedReward), USDC_1);
        freeManagedReward.notifyRewardAmount(address(USDC), usdcReward);
        vm.stopPrank();

        // simulate rebases for epoch 2:
        deal(address(AERO), address(distributor), TOKEN_1);
        vm.startPrank(address(distributor));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.depositFor(mTokenId, TOKEN_1);
        vm.stopPrank();
        supply += TOKEN_1;

        /// withdraw from managed nft early
        /// not entitled to rewards distributed this week (both free / locked)
        skip(1 hours);
        pre = AERO.balanceOf(address(escrow));
        vm.prank(address(owner2));
        voter.withdrawManaged(tokenId2);
        post = AERO.balanceOf(address(escrow));

        // check locked rewards transferred to VotingEscrow
        assertEq(post - pre, TOKEN_1);
        // rebase from this week + locked rewards for tokenId
        assertEq(AERO.balanceOf(address(lockedManagedReward)), TOKEN_1 * 2);

        // check nfts are configured correctly
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 127612800);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.supply(), supply);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), TOKEN_1);
        assertEq(freeManagedReward.earned(address(AERO), tokenId), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(freeManagedReward.earned(address(USDC), tokenId), 0);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(freeManagedReward.earned(address(USDC), tokenId2), 0);

        skip(1 hours);
        voter.poke(mTokenId);

        // owner 2 claims rewards
        pre = AERO.balanceOf(address(owner2));
        uint256 usdcPre = USDC.balanceOf(address(owner2));
        vm.prank(address(owner2));
        freeManagedReward.getReward(tokenId2, rewards);
        post = AERO.balanceOf(address(owner2));
        uint256 usdcPost = USDC.balanceOf(address(owner2));

        assertEq(post - pre, ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(usdcPost - usdcPre, 0);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(USDC), tokenId2), 0);

        skipToNextEpoch(1);

        // epoch 3:

        /// state of gauge votes:
        /// mTokenId contribution ~= 3 / 4
        /// tokenId3 contribution ~= 1 / 4

        // owner receives all rewards, owner2 receives nothing
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), TOKEN_1 * 2);
        assertEq(freeManagedReward.earned(address(AERO), tokenId), ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(freeManagedReward.earned(address(USDC), tokenId), usdcReward);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), 0);
        assertEq(freeManagedReward.earned(address(USDC), tokenId2), 0);

        skip(1 hours);

        pre = AERO.balanceOf(address(escrow));
        voter.withdrawManaged(tokenId);
        post = AERO.balanceOf(address(escrow));

        // check locked rewards transferred to VotingEscrow
        assertEq(post - pre, TOKEN_1 * 2);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), 0);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);

        // check nfts are configured correctly
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 3);
        assertEq(locked.end, 128217600);
        assertEq(locked.isPermanent, false);

        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        skip(1 hours);

        // claim rewards after withdrawal
        pre = AERO.balanceOf(address(owner));
        usdcPre = USDC.balanceOf(address(owner));
        freeManagedReward.getReward(tokenId, rewards);
        post = AERO.balanceOf(address(owner));
        usdcPost = USDC.balanceOf(address(owner));

        assertEq(post - pre, ((TOKEN_1 * 2) * 3) / 4 / 2);
        assertEq(usdcPost - usdcPre, usdcReward);
        assertEq(freeManagedReward.earned(address(AERO), tokenId), 0);
        assertEq(freeManagedReward.earned(address(USDC), tokenId), 0);

        // withdraw managed nft votes from pool
        vm.prank(address(owner4));
        voter.reset(mTokenId);

        skipToNextEpoch(1 hours + 1);

        // epoch 4:
        // test normal operation of nft post-withdrawal

        /// state of gauge votes
        /// tokenId contribution: ~= 3 / 4
        /// tokenId3 contribution: ~= 1 / 4

        // owner votes for pool now
        voter.vote(tokenId, pools, weights);

        // create aero bribe for epoch 4
        _createBribeWithAmount(bribeVotingReward, address(AERO), TOKEN_1);

        skipToNextEpoch(1);

        // test normal nft behavior post withdrawal
        // ~= approx TOKEN_1 * 3 / 4, some drift due to voting power decay
        assertEq(bribeVotingReward.earned(address(AERO), tokenId), 749095271054930289);

        pre = AERO.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(tokenId, rewards);
        post = AERO.balanceOf(address(owner));

        assertEq(post - pre, 749095271054930289);
    }

    function testTransferManagedNftFlow() public {
        // epoch 0:
        // create managed nft
        // deposit into managed nft
        // simulate rebases for epoch 0
        uint256 supply = escrow.supply();

        // switch allowedManager to allow owner4 to create managed lock
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner4));

        vm.prank(address(owner4));
        uint256 mTokenId = escrow.createManagedLockFor(address(owner4));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));

        skip(1 hours);
        voter.depositManaged(tokenId, mTokenId);

        // check deposit successful
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);

        vm.prank(address(owner2));
        voter.depositManaged(tokenId2, mTokenId);

        assertEq(escrow.idToManaged(tokenId2), mTokenId);
        assertEq(escrow.weights(tokenId2, mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId2), 0);

        IVotingEscrow.LockedBalance memory locked;
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        // net supply unchanged
        assertEq(escrow.supply(), supply);

        // test voting
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        address[] memory rewards = new address[](2);
        rewards[0] = address(AERO);
        rewards[1] = address(USDC);

        // create aero bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(AERO), TOKEN_1);

        skip(1 hours + 1);

        vm.prank(address(owner4));
        voter.vote(mTokenId, pools, weights);

        skipToNextEpoch(1);

        // epoch 1:
        // reset managed nft
        // transfer managed nft to new owner

        // collect rewards from bribe
        uint256 pre = AERO.balanceOf(address(owner4));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        uint256 post = AERO.balanceOf(address(owner4));
        assertEq(post - pre, TOKEN_1);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner4));
        AERO.approve(address(freeManagedReward), TOKEN_1 * 2);
        freeManagedReward.notifyRewardAmount(address(AERO), TOKEN_1);
        vm.stopPrank();

        skip(1 hours);
        vm.startPrank(address(owner4));
        voter.reset(mTokenId);
        escrow.transferFrom(address(owner4), address(owner3), mTokenId);
        vm.stopPrank();

        // required to overcome flash nft protection after transfer
        vm.roll(block.timestamp + 1);

        skipToNextEpoch(1);

        // epoch 2:
        // managed nft votes for pool again

        assertEq(freeManagedReward.earned(address(AERO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), TOKEN_1 / 2);

        // create aero bribe for next epoch
        _createBribeWithAmount(bribeVotingReward, address(AERO), TOKEN_1 * 2);

        skip(1 hours);
        // user withdraws from nft
        pre = AERO.balanceOf(address(escrow));
        voter.withdrawManaged(tokenId);
        post = AERO.balanceOf(address(escrow));

        assertEq(post - pre, 0);

        // check nfts are configured correctly
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127612800);
        assertEq(locked.isPermanent, false);

        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        skip(1 hours);

        vm.prank(address(owner3));
        voter.vote(mTokenId, pools, weights);

        skipToNextEpoch(1);

        // epoch 3:
        // claim and distribute rewards

        assertEq(freeManagedReward.earned(address(AERO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), TOKEN_1 / 2);

        skipAndRoll(1);
        escrow.setManagedState(mTokenId, true);
        // normal operation despite managed nft can no longer accept new deposits

        // collect rewards from bribe
        pre = AERO.balanceOf(address(owner3));
        vm.prank(address(voter));
        bribeVotingReward.getReward(mTokenId, rewards);
        post = AERO.balanceOf(address(owner3));
        assertEq(post - pre, TOKEN_1 * 2);

        // distribute reward to managed nft depositors
        vm.startPrank(address(owner3));
        AERO.approve(address(freeManagedReward), TOKEN_1 * 2);
        freeManagedReward.notifyRewardAmount(address(AERO), TOKEN_1 * 2);
        vm.stopPrank();

        skipToNextEpoch(1);

        // epoch 4:

        assertEq(freeManagedReward.earned(address(AERO), tokenId), TOKEN_1 / 2);
        assertEq(freeManagedReward.earned(address(AERO), tokenId2), (TOKEN_1 * 5) / 2);

        skip(1 hours);
        pre = AERO.balanceOf(address(escrow));
        vm.prank(address(owner2));
        voter.withdrawManaged(tokenId2);
        post = AERO.balanceOf(address(escrow));

        assertEq(post - pre, 0);
    }

    function testManagedNftRebaseFlow() public {
        // simple multi epoch rebase claim flow
        // epoch 0: minter does not mint
        AERO.approve(address(escrow), TOKEN_1M);
        tokenId = escrow.createLock(TOKEN_1M, MAX_TIME);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1M);
        tokenId2 = escrow.createLock(TOKEN_1M, MAX_TIME);
        // lock permanent to make mTokenId and tokenId2 balances equal
        escrow.lockPermanent(tokenId2);
        vm.stopPrank();
        uint256 supply = escrow.supply();

        vm.prank(address(governor));
        uint256 mTokenId = escrow.createManagedLockFor(address(owner4));
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));

        skip(1 hours);
        voter.depositManaged(tokenId, mTokenId);

        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1M);
        assertEq(escrow.balanceOfNFT(tokenId), 0);

        IVotingEscrow.LockedBalance memory locked;
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.supply(), supply);

        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;

        vm.prank(address(owner4));
        voter.vote(mTokenId, pools, weights);

        vm.prank(address(owner2));
        voter.vote(tokenId2, pools, weights);

        // epoch 1: minter mints rebases for epoch 0
        skipToNextEpoch(1);
        minter.updatePeriod();

        skip(1 hours);
        assertEq(distributor.claimable(mTokenId), 2303992474702363587666916);
        assertEq(distributor.claimable(tokenId2), 2303992474702363587666916);
        assertGt(AERO.balanceOf(address(distributor)), 0);

        // epoch 2: claim rebases
        skipToNextEpoch(1);
        minter.updatePeriod();

        uint256 rebase = distributor.claim(mTokenId);
        assertEq(rebase, 4723887052133285931305344);
        // check locked, user points and global points update correctly on rebase claim
        locked = escrow.locked(mTokenId);
        assertEq(convert(locked.amount), TOKEN_1M + rebase);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly when rebases are claimed
        assertEq(escrow.userPointEpoch(mTokenId), 3);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(mTokenId, 3);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1814401);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, 5723887052133285931305344); // TOKEN_1M + rebase
        assertEq(escrow.balanceOfNFT(mTokenId), 5723887052133285931305344);

        // check global point updates correctly when rebases are claimed
        assertEq(escrow.epoch(), 6);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(6);
        // bias / slope not zero due to tokenIds created in _setUp()
        assertEq(convert(globalPoint.bias), 2963013674496024015); // (TOKEN_1 * 3 / MAXTIME) * (126403200 - 1814401)
        assertEq(convert(globalPoint.slope), 23782343985); // TOKEN_1 * 3 / MAXTIME
        assertEq(globalPoint.ts, 1814401);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, 6723887052133285931305344); // TOKEN_1M * 2 + rebase
        assertEq(escrow.totalSupply(), 6723887052133285931305344 + 2963013674496024015); // TOKEN_1M * 2 + rebase + bias

        uint256 managedRebaseTotal = rebase;
        assertGt(rebase, 0);
        assertEq(distributor.claim(tokenId2), rebase);

        uint256 tokenAmount = TOKEN_1M + rebase;
        supply += rebase * 2;

        // check rebase accrues to nfts + lmr
        assertEq(uint256(uint128(escrow.locked(mTokenId).amount)), tokenAmount);
        assertEq(uint256(uint128(escrow.locked(tokenId2).amount)), tokenAmount);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), managedRebaseTotal);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), 0);
        assertEq(escrow.supply(), supply);

        // epoch 3: claim rebases
        skipToNextEpoch(1);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), managedRebaseTotal);
        minter.updatePeriod();

        rebase = distributor.claim(mTokenId);

        // check locked, user points and global points update correctly on rebase claim
        locked = escrow.locked(mTokenId);
        assertEq(convert(locked.amount), tokenAmount + rebase);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly when rebases are claimed
        assertEq(escrow.userPointEpoch(mTokenId), 4);
        userPoint = escrow.userPointHistory(mTokenId, 4);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 2419201);
        assertEq(userPoint.blk, 4);
        assertEq(userPoint.permanent, tokenAmount + rebase);
        assertEq(escrow.balanceOfNFT(mTokenId), tokenAmount + rebase);

        // check global point updates correctly when rebases are claimed
        assertEq(escrow.epoch(), 8);
        globalPoint = escrow.pointHistory(8);
        // bias / slope not zero due to tokenIds created in _setUp()
        assertEq(convert(globalPoint.bias), 2948630112853896015); // (TOKEN_1 * 3 / MAXTIME) * (126403200 - 2419201)
        assertEq(convert(globalPoint.slope), 23782343985); // TOKEN_1 * 3 / MAXTIME
        assertEq(globalPoint.ts, 2419201);
        assertEq(globalPoint.blk, 4);
        assertEq(globalPoint.permanentLockBalance, tokenAmount * 2 + rebase);
        assertEq(escrow.totalSupply(), tokenAmount * 2 + rebase + 2948630112853896015);

        managedRebaseTotal += rebase;
        assertGt(rebase, 0);
        assertEq(distributor.claim(tokenId2), rebase);
        tokenAmount += rebase;
        supply += rebase * 2;

        assertEq(uint256(uint128(escrow.locked(mTokenId).amount)), tokenAmount);
        assertEq(uint256(uint128(escrow.locked(tokenId2).amount)), tokenAmount);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), managedRebaseTotal);
        // current epoch's rebases yet to accrue
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), managedRebaseTotal - rebase);
        assertEq(escrow.supply(), supply);

        // epoch 4: withdraw from managed
        skipToNextEpoch(1);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), managedRebaseTotal);

        skip(1 hours);
        uint256 pre = AERO.balanceOf(address(escrow));
        voter.withdrawManaged(tokenId);
        uint256 post = AERO.balanceOf(address(escrow));

        assertEq(post - pre, managedRebaseTotal);
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M + managedRebaseTotal);
        assertEq(locked.end, 128822400);
        assertEq(locked.isPermanent, false);
        assertEq(lockedManagedReward.earned(address(AERO), tokenId), 0);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);
    }
}
