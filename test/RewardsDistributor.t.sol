// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract RewardsDistributorTest is BaseTest {
    event Claimed(uint256 indexed tokenId, uint256 indexed epochStart, uint256 indexed epochEnd, uint256 amount);

    function _setUp() public override {
        // timestamp: 604801
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skip(1);

        address[] memory pools = new address[](2);
        pools[0] = address(pool);
        pools[1] = address(pool2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 1;
        weights[1] = 1;

        skip(1 hours);
        voter.vote(tokenId, pools, weights);
    }

    function testInitialize() public {
        assertEq(distributor.startTime(), 604800);
        assertEq(distributor.lastTokenTime(), 604800);
        assertEq(distributor.token(), address(AERO));
        assertEq(address(distributor.ve()), address(escrow));
    }

    function testClaim() public {
        skipToNextEpoch(1 days); // epoch 1, ts: 1296000, blk: 2

        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 127008000);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 1);
        assertEq(convert(userPoint.slope), TOKEN_1M / MAXTIME); // TOKEN_1M / MAXTIME
        assertEq(convert(userPoint.bias), 996575342465753345952000); // (TOKEN_1M / MAXTIME) * (127008000 - 1296000)
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        vm.stopPrank();

        locked = escrow.locked(tokenId2);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 127008000);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId2), 1);
        userPoint = escrow.userPointHistory(tokenId2, 1);
        assertEq(convert(userPoint.slope), TOKEN_1M / MAXTIME); // TOKEN_1M / MAXTIME
        assertEq(convert(userPoint.bias), 996575342465753345952000); // (TOKEN_1M / MAXTIME) * (127008000 - 1296000)
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);

        // epoch 2
        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 1152722779439564982373378);
        assertEq(distributor.claimable(tokenId2), 1152722779439564982373378);

        // epoch 3
        skipToNextEpoch(0); // distribute epoch 2's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 3574509985698454145913662);
        assertEq(distributor.claimable(tokenId2), 3574509985698454145913662);

        // epoch 4
        skipToNextEpoch(0); // distribute epoch 3's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 6100132525537650835610574);
        assertEq(distributor.claimable(tokenId2), 6100132525537650835610574);

        // epoch 5
        skipToNextEpoch(0); // distribute epoch 4's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 8723818542033905018192152);
        assertEq(distributor.claimable(tokenId2), 8723818542033905018192152);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 1209600, 3628800, 8723818542033905018192152);
        distributor.claim(tokenId);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);
        assertEq(postLocked.amount - preLocked.amount, 8723818542033905018192152);
        assertEq(postLocked.end, 127008000);
        assertEq(postLocked.isPermanent, false);
    }

    function testClaimWithPermanentLocks() public {
        skipToNextEpoch(1 days); // epoch 1, ts: 1296000, blk: 2

        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 1);
        assertEq(convert(userPoint.slope), 0);
        assertEq(convert(userPoint.bias), 0);
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1M);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId2);
        vm.stopPrank();

        locked = escrow.locked(tokenId2);
        assertEq(convert(locked.amount), TOKEN_1M);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId2), 1);
        userPoint = escrow.userPointHistory(tokenId2, 1);
        assertEq(convert(userPoint.slope), 0);
        assertEq(convert(userPoint.bias), 0);
        assertEq(userPoint.ts, 1296000);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1M);

        // epoch 2
        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 1151999383693450653246265);
        assertEq(distributor.claimable(tokenId2), 1151999383693450653246265);

        // epoch 3
        skipToNextEpoch(0); // distribute epoch 2's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 3571896700737325138420140);
        assertEq(distributor.claimable(tokenId2), 3571896700737325138420140);

        // epoch 4
        skipToNextEpoch(0); // distribute epoch 3's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 6095329697846513945318258);
        assertEq(distributor.claimable(tokenId2), 6095329697846513945318258);

        // epoch 5
        skipToNextEpoch(0); // distribute epoch 4's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 8716604666283848308450898);
        assertEq(distributor.claimable(tokenId2), 8716604666283848308450898);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 1209600, 3628800, 8716604666283848308450898);
        distributor.claim(tokenId);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);
        assertEq(postLocked.amount - preLocked.amount, 8716604666283848308450898);
        assertEq(postLocked.end, 0);
        assertEq(postLocked.isPermanent, true);
    }

    function testClaimWithBothLocks() public {
        skipToNextEpoch(1 days); // epoch 1, ts: 1296000, blk: 2

        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        vm.stopPrank();

        // expect permanent lock to earn more rebases
        // epoch 2
        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 1156718549995046434886653);
        assertEq(distributor.claimable(tokenId2), 1148003556390937213889369);

        // epoch 3
        skipToNextEpoch(0); // distribute epoch 2's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 3592576292985905298081775);
        assertEq(distributor.claimable(tokenId2), 3553830195833140059510403);

        // epoch 4
        skipToNextEpoch(0); // distribute epoch 3's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 6138904736852107630169458);
        assertEq(distributor.claimable(tokenId2), 6056557145435464774714642);

        // epoch 5
        skipToNextEpoch(0); // distribute epoch 4's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 8790443106370251794057763);
        assertEq(distributor.claimable(tokenId2), 8649979626504650436393148);

        uint256 pre = convert(escrow.locked(tokenId).amount);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 1209600, 3628800, 8790443106370251794057763);
        distributor.claim(tokenId);
        uint256 post = convert(escrow.locked(tokenId).amount);

        assertEq(post - pre, 8790443106370251794057763);
    }

    function testClaimWithLockCreatedMoreThan50EpochsLater() public {
        for (uint256 i = 0; i < 55; i++) {
            skipToNextEpoch(0);
            minter.updatePeriod();
        }

        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);

        skipToNextEpoch(0);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 2495582574387838171855988);
        assertEq(distributor.claimable(tokenId2), 2495582574387838171855988);

        skipToNextEpoch(0);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 4966371507343622027541916);
        assertEq(distributor.claimable(tokenId2), 4966371507343622027541916);

        uint256 pre = convert(escrow.locked(tokenId).amount);
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 33868800, 35078400, 4966371507343622027541916);
        distributor.claim(tokenId);
        uint256 post = convert(escrow.locked(tokenId).amount);

        assertEq(post - pre, 4966371507343622027541916);
    }

    function testClaimWithIncreaseAmountOnEpochFlip() public {
        skipToNextEpoch(1 days); // epoch 1
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);

        skipToNextEpoch(0); // distribute epoch 1's rebases
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 1152722779439564982373378);
        assertEq(distributor.claimable(tokenId2), 1152722779439564982373378);

        skipToNextEpoch(0);
        assertEq(distributor.claimable(tokenId), 1152722779439564982373378);
        assertEq(distributor.claimable(tokenId2), 1152722779439564982373378);
        // making lock larger on flip should not impact claimable
        AERO.approve(address(escrow), TOKEN_1M);
        escrow.increaseAmount(tokenId, TOKEN_1M);
        minter.updatePeriod(); // epoch 1's rebases available
        assertEq(distributor.claimable(tokenId), 3574509985698454145913662);
        assertEq(distributor.claimable(tokenId2), 3574509985698454145913662);
    }

    function testClaimWithExpiredNFT() public {
        // test reward claims to expired NFTs are distributed as unlocked AERO
        // ts: 608402
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, WEEK * 4);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 4996770462023280576149678);

        for (uint256 i = 0; i < 4; i++) {
            minter.updatePeriod();
            skipToNextEpoch(1);
        }
        minter.updatePeriod();

        assertGt(distributor.claimable(tokenId), 4996770462023280576149678); // accrued rebases

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertGt(block.timestamp, locked.end); // lock expired

        uint256 rebase = distributor.claimable(tokenId);
        uint256 pre = AERO.balanceOf(address(owner));
        vm.expectEmit(true, true, true, true, address(distributor));
        emit Claimed(tokenId, 604800, 3628800, 15491459054552564388715110);
        distributor.claim(tokenId);
        uint256 post = AERO.balanceOf(address(owner));

        locked = escrow.locked(tokenId); // update locked value post claim
        assertEq(post - pre, rebase); // expired rebase distributed as unlocked AERO
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M); // expired nft locked balance unchanged
    }

    function testClaimManyWithExpiredNFT() public {
        // test claim many with one expired nft and one normal nft
        // ts: 608402
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, WEEK * 4);
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertEq(distributor.claimable(tokenId), 68580676158366995877271);
        assertEq(distributor.claimable(tokenId2), 4732064084665303035783005);

        for (uint256 i = 0; i < 4; i++) {
            minter.updatePeriod();
            skipToNextEpoch(1);
        }
        minter.updatePeriod();

        assertGt(distributor.claimable(tokenId), 0); // accrued rebases
        assertGt(distributor.claimable(tokenId2), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertGt(block.timestamp, locked.end); // lock expired

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId;
        tokenIds[1] = tokenId2;

        uint256 rebase = distributor.claimable(tokenId);
        uint256 rebase2 = distributor.claimable(tokenId2);

        uint256 pre = AERO.balanceOf(address(owner));
        assertTrue(distributor.claimMany(tokenIds));
        uint256 post = AERO.balanceOf(address(owner));

        locked = escrow.locked(tokenId); // update locked value post claim
        IVotingEscrow.LockedBalance memory postLocked2 = escrow.locked(tokenId2);

        assertEq(post - pre, rebase); // expired rebase distributed as unlocked AERO
        assertEq(uint256(uint128(locked.amount)), TOKEN_1M); // expired nft locked balance unchanged
        assertEq(uint256(uint128(postLocked2.amount)) - uint256(uint128(locked.amount)), rebase2); // rebase accrued to normal nft
    }

    function testClaimRebaseWithManagedLocks() public {
        minter.updatePeriod(); // does nothing
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId2);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        voter.depositManaged(tokenId2, mTokenId);

        skipAndRoll(1 hours); // created at epoch 0 + 1 days + 1 hours
        uint256 tokenId3 = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId3);

        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 0);
        assertEq(distributor.claimable(mTokenId), 0);

        skipToNextEpoch(0); // epoch 1
        minter.updatePeriod();

        // epoch 0 rebases distributed
        assertEq(distributor.claimable(tokenId), 1472666117281913241935482);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 1472666117281913241935482);
        assertEq(distributor.claimable(mTokenId), 1472666117281913241935482);

        skipAndRoll(1 days); // deposit @ epoch 1 + 1 days
        voter.depositManaged(tokenId3, mTokenId);

        skipToNextEpoch(0); // epoch 2
        minter.updatePeriod();

        // epoch 1 rebases distributed
        assertEq(distributor.claimable(tokenId), 3034974130530850064652066);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 1472666117281913241935482);
        assertEq(distributor.claimable(mTokenId), 4597282143779786887368651);
        distributor.claim(mTokenId); // claim token rewards
        assertEq(distributor.claimable(mTokenId), 0);

        uint256 tokenId4 = escrow.createLock(TOKEN_1M, MAXTIME); // lock created in epoch 2
        escrow.lockPermanent(tokenId4);

        skipToNextEpoch(1 hours); // epoch 3
        minter.updatePeriod();

        // epoch 2 rebases distributed
        assertEq(distributor.claimable(tokenId), 3525007759056630145279165);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 1472666117281913241935482); // claimable unchanged
        assertEq(distributor.claimable(tokenId4), 490033628525780080627099); // claim rebases from last epoch
        assertEq(distributor.claimable(mTokenId), 3232890107324746138960350);

        skipToNextEpoch(0); // epoch 4
        minter.updatePeriod();

        // rewards for epoch 2 locks
        assertEq(distributor.claimable(tokenId), 4055378562868735311657493);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(tokenId3), 1472666117281913241935482); // claimable unchanged
        assertEq(distributor.claimable(tokenId4), 1020404432337885247005427);
        assertEq(distributor.claimable(mTokenId), 6731895940896480078601988);

        skipAndRoll(1 hours + 1);
        voter.withdrawManaged(tokenId3);

        for (uint256 i = 0; i <= 6; i++) {
            if (i == tokenId2) continue;
            distributor.claim(i);
            assertEq(distributor.claimable(i), 0);
        }

        assertLt(AERO.balanceOf(address(distributor)), 100); // dust
    }

    function testClaimRebaseWithDepositManaged() public {
        minter.updatePeriod(); // does nothing
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_10M);
        uint256 tokenId = escrow.createLock(TOKEN_10M, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.stopPrank();

        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_10M);
        uint256 tokenId2 = escrow.createLock(TOKEN_10M, MAXTIME);
        escrow.lockPermanent(tokenId2);
        vm.stopPrank();
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(distributor.claimable(tokenId), 0);
        assertEq(distributor.claimable(tokenId2), 0);
        assertEq(distributor.claimable(mTokenId), 0);

        skipToNextEpoch(0); // epoch 1
        minter.updatePeriod();

        // epoch 0 rebases distributed
        assertEq(distributor.claimable(tokenId), 899999895791101226577090);
        assertEq(distributor.claimable(tokenId2), 899999895791101226577090);
        assertEq(distributor.claimable(mTokenId), 0);

        skipAndRoll(1 days);
        vm.prank(address(owner3));
        voter.depositManaged(tokenId2, mTokenId);

        assertEq(distributor.claimable(tokenId), 899999895791101226577090);
        assertEq(distributor.claimable(tokenId2), 899999895791101226577090);
        assertEq(distributor.claimable(mTokenId), 0);

        skipToNextEpoch(1 hours); // epoch 2
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 2082507730394926619421556);
        assertEq(distributor.claimable(tokenId2), 899999895791101226577090); // claimable unchanged
        assertEq(distributor.claimable(mTokenId), 1182507834603825392844466); // rebase earned by tokenId2

        skipAndRoll(1);
        vm.prank(address(owner3));
        voter.withdrawManaged(tokenId2);

        skipToNextEpoch(0); // epoch 3
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 3536190096302840449423561);
        assertEq(distributor.claimable(tokenId2), 2342729871836028977218998);
        assertEq(distributor.claimable(mTokenId), 1182507834603825392844466); // claimable unchanged
    }

    function testCannotClaimRebaseWithLockedNFT() public {
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        escrow.lockPermanent(tokenId);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skipToNextEpoch(2 hours); // epoch 1
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 4745500980370920284233136);
        assertEq(distributor.claimable(mTokenId), 0);

        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1 days); // epoch 3
        minter.updatePeriod();

        vm.expectRevert(IRewardsDistributor.NotManagedOrNormalNFT.selector);
        distributor.claim(tokenId);
    }

    function testCannotClaimBeforeUpdatePeriod() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1M, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1M * 8, MAXTIME);

        skipToNextEpoch(2 hours); // epoch 1
        minter.updatePeriod();

        assertEq(distributor.claimable(tokenId), 370382813492688374288331);
        assertEq(distributor.claimable(tokenId2), 2963062507941507227914498);

        skipToNextEpoch(1 hours); // epoch 3
        vm.expectRevert(IRewardsDistributor.UpdatePeriod.selector);
        distributor.claim(tokenId);

        skipAndRoll(1 hours);
        minter.updatePeriod();

        distributor.claim(tokenId);
    }

    function testCannotCheckpointTokenIfNotMinter() public {
        vm.expectRevert(IRewardsDistributor.NotMinter.selector);
        vm.prank(address(owner2));
        distributor.checkpointToken();
    }

    function testClaimBeforeLockedEnd() public {
        uint256 duration = WEEK * 12;
        vm.startPrank(address(owner));
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, duration);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertGt(distributor.claimable(tokenId), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        vm.warp(locked.end - 1);
        assertEq(block.timestamp, locked.end - 1);
        minter.updatePeriod();

        // Rebase should deposit into veNFT one second before expiry
        distributor.claim(tokenId);
        locked = escrow.locked(tokenId);
        assertGt(uint256(uint128((locked.amount))), TOKEN_1M);
    }

    function testClaimOnLockedEnd() public {
        uint256 duration = WEEK * 12;
        vm.startPrank(address(owner));
        AERO.approve(address(escrow), TOKEN_1M);
        uint256 tokenId = escrow.createLock(TOKEN_1M, duration);

        skipToNextEpoch(1);
        minter.updatePeriod();
        assertGt(distributor.claimable(tokenId), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        vm.warp(locked.end);
        assertEq(block.timestamp, locked.end);
        minter.updatePeriod();

        // Rebase should deposit into veNFT one second before expiry
        uint256 balanceBefore = AERO.balanceOf(address(owner));
        distributor.claim(tokenId);
        assertGt(AERO.balanceOf(address(owner)), balanceBefore);
    }
}
