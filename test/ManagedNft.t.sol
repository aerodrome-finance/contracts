// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract ManagedNftTest is BaseTest {
    LockedManagedReward lockedManagedReward;
    FreeManagedReward freeManagedReward;

    event DepositManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );
    event WithdrawManaged(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _mTokenId,
        uint256 _weight,
        uint256 _ts
    );
    event MetadataUpdate(uint256 _tokenId);

    function assertNeq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }

    function testCreateManagedLockFor() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        assertEq(uint256(escrow.escrowType(mTokenId)), uint256(IVotingEscrow.EscrowType.MANAGED));
        assertEq(escrow.tokenId(), 1);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.supply(), 0);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(mTokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(mTokenId, 1);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604801);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 1);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(1);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 604801);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, 0);

        // check voting checkpoints
        assertEq(escrow.numCheckpoints(mTokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(mTokenId, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check locked / free rewards addresses have been set
        assertNeq(escrow.managedToLocked(1), address(0));
        assertNeq(escrow.managedToFree(1), address(0));
        assertFalse(escrow.deactivated(mTokenId));
    }

    function testCannotDepositManagedIfNotVoter() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.locked(tokenId).end, 126403200);

        skip(1 weeks);
        vm.expectRevert(IVotingEscrow.NotVoter.selector);
        escrow.depositManaged(tokenId, mTokenId);
    }

    function testCannotDepositManagedUntilAfterDistributeWindow() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2)); // 1

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME); // 2
        assertEq(escrow.locked(tokenId).end, 126403200);

        skipToNextEpoch(0);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.depositManaged(tokenId, mTokenId);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.depositManaged(tokenId, mTokenId);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.depositManaged(tokenId, mTokenId);

        skip(1);
        voter.depositManaged(tokenId, mTokenId);
    }

    function testDepositManagedWithNormalNFT() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.locked(tokenId).end, 126403200);
        assertEq(escrow.slopeChanges(126403200), -7927447995);
        uint256 supply = escrow.supply();

        skipToNextEpoch(1 hours + 1);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit DepositManaged(address(owner), tokenId, mTokenId, TOKEN_1, 1213201);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        voter.depositManaged(tokenId, mTokenId);

        // updates balance of managed nft
        assertEq(voter.lastVoted(tokenId), 1213201);
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.LOCKED));

        IVotingEscrow.LockedBalance memory locked;

        // zero out existing deposit
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        // check depositing user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // transfer deposit to managed nft, max lock
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point updates correctly
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1);

        // check global point updates correctly
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 1213201);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        // check voting checkpoints
        assertEq(escrow.numCheckpoints(mTokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(mTokenId, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check deposit represented in ve
        assertEq(escrow.balanceOfNFT(mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), TOKEN_1);

        // check deposit represented in locked / free managed rewards
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(lockedManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(lockedManagedReward.totalSupply(), TOKEN_1);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(freeManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(freeManagedReward.totalSupply(), TOKEN_1);
        assertEq(escrow.slopeChanges(126403200), 0);
    }

    function testDepositManagedWithDelegatingManagedNFT() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        vm.prank(address(owner2));
        escrow.delegate(mTokenId, tokenId2);
        uint256 supply = escrow.supply();
        assertEq(escrow.slopeChanges(126403200), -15854895990);

        skipToNextEpoch(1 hours + 1);
        vm.expectEmit(true, false, false, false, address(escrow));
        emit DepositManaged(address(owner), tokenId, mTokenId, TOKEN_1, 1213201);
        voter.depositManaged(tokenId, mTokenId);

        // updates balance of managed nft
        assertEq(voter.lastVoted(tokenId), 1213201);
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.LOCKED));

        IVotingEscrow.LockedBalance memory locked;

        // zero out existing deposit
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        // check depositing user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // transfer deposit to managed nft
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point updates correctly
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1);

        // check global point updates correctly
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 992437206566602005); // TOKEN_1 / MAXTIME * (126403200 - 1213201)
        assertEq(convert(globalPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(globalPoint.ts, 1213201);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        // check voting checkpoints of managed nft
        assertEq(escrow.numCheckpoints(mTokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(mTokenId, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId2);

        // check voting checkpoints of delegatee
        assertEq(escrow.numCheckpoints(tokenId2), 2);
        checkpoint = escrow.checkpoints(tokenId2, 1);
        assertEq(checkpoint.fromTimestamp, 1213201);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);

        // check deposit represented in ve
        assertEq(escrow.balanceOfNFT(mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), TOKEN_1 + 992437206566602005);
        assertEq(escrow.getPastVotes(address(owner), tokenId2, 1213201), TOKEN_1 + 992437206566602005);
        assertEq(escrow.getPastVotes(address(owner2), mTokenId, 1213201), 0);

        // check deposit represented in locked / free managed rewards
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(lockedManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(lockedManagedReward.totalSupply(), TOKEN_1);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(freeManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(freeManagedReward.totalSupply(), TOKEN_1);
        assertEq(escrow.slopeChanges(126403200), -7927447995);
    }

    function testDepositManagedWithPermanentLock() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.locked(tokenId).end, 126403200);
        uint256 supply = escrow.supply();
        assertEq(escrow.slopeChanges(126403200), -7927447995);
        escrow.lockPermanent(tokenId);
        assertEq(escrow.slopeChanges(126403200), 0);
        assertEq(escrow.numCheckpoints(tokenId), 1);

        skipToNextEpoch(1 hours + 1);
        vm.expectEmit(true, false, false, false, address(escrow));
        emit DepositManaged(address(owner), tokenId, mTokenId, TOKEN_1, 1213201);
        voter.depositManaged(tokenId, mTokenId);

        // updates balance of managed nft
        assertEq(voter.lastVoted(tokenId), 1213201);
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.LOCKED));

        IVotingEscrow.LockedBalance memory locked;
        IVotingEscrow.UserPoint memory userPoint;

        // zero out existing deposit
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        // check depositor user point
        assertEq(escrow.userPointEpoch(tokenId), 2);
        userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // transfer deposit to managed nft
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1);

        // check global point
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 1213201);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        // check deposit represented in ve
        assertEq(escrow.balanceOfNFT(mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), TOKEN_1);

        // check deposit represented in locked / free managed rewards
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(lockedManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(lockedManagedReward.totalSupply(), TOKEN_1);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(freeManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(freeManagedReward.totalSupply(), TOKEN_1);
        assertEq(escrow.numCheckpoints(tokenId), 1);
        assertEq(escrow.slopeChanges(126403200), 0);
    }

    function testDepositManagedWithDelegatingPermanentLock() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId); // no slope change contribution
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 supply = escrow.supply();
        vm.stopPrank();
        skipAndRoll(1);
        escrow.delegate(tokenId, tokenId2);
        assertEq(escrow.slopeChanges(126403200), -7927447995); // contribution from tokenId2 only

        skipToNextEpoch(1 hours + 1);
        vm.expectEmit(true, false, false, false, address(escrow));
        emit DepositManaged(address(owner), tokenId, mTokenId, TOKEN_1, 1213201);
        voter.depositManaged(tokenId, mTokenId);

        // updates balance of managed nft
        assertEq(voter.lastVoted(tokenId), 1213201);
        assertEq(escrow.idToManaged(tokenId), mTokenId);
        assertEq(escrow.weights(tokenId, mTokenId), TOKEN_1);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.LOCKED));

        IVotingEscrow.LockedBalance memory locked;
        IVotingEscrow.UserPoint memory userPoint;

        // zero out existing deposit
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        // check depositor user point
        assertEq(escrow.userPointEpoch(tokenId), 2);
        userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, 0);

        // transfer deposit to managed nft, max lock
        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1213201);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, TOKEN_1);

        // check global point
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 992437206566602005); // nft 2 decayed by one week
        assertEq(convert(globalPoint.slope), 7927447995);
        assertEq(globalPoint.ts, 1213201);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        // check deposit represented in ve
        assertEq(escrow.balanceOfNFT(mTokenId), TOKEN_1);
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.supply(), supply);
        assertEq(escrow.balanceOfNFT(tokenId2), 992437206566602005);
        assertEq(escrow.totalSupply(), TOKEN_1 + 992437206566602005);

        // check deposit represented in locked / free managed rewards
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(lockedManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(lockedManagedReward.totalSupply(), TOKEN_1);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(freeManagedReward.balanceOf(tokenId), TOKEN_1);
        assertEq(freeManagedReward.totalSupply(), TOKEN_1);

        // check depositor delegation reset
        assertEq(escrow.numCheckpoints(tokenId), 3);
        assertEq(escrow.delegates(tokenId), 0);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(tokenId, 2);
        assertEq(checkpoint.fromTimestamp, 1213201);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check prior delegatee delegated voting power reset
        assertEq(escrow.numCheckpoints(tokenId2), 3);
        assertEq(escrow.delegates(tokenId2), 0);
        checkpoint = escrow.checkpoints(tokenId2, 2);
        assertEq(checkpoint.fromTimestamp, 1213201);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.slopeChanges(126403200), -7927447995);
    }

    function testCannotDepositManagedIntoNonManagedNft() public {
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);
        escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1 hours);

        vm.expectRevert(IVotingEscrow.NotManagedNFT.selector);
        voter.depositManaged(1, 2);
    }

    function testCannotDepositManagedWithManagedNft() public {
        skipAndRoll(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        uint256 mTokenId2 = escrow.createManagedLockFor(address(owner));

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        voter.depositManaged(mTokenId2, mTokenId);
    }

    function testCannotDepositManagedWithAlreadyLockedNft() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1 hours);

        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1 hours + 1);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotDepositManagedWithAlreadyVotedNft() public {
        skip(1 hours + 1);

        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        escrow.createManagedLockFor(address(owner));

        skip(1 hours);

        vm.expectRevert(IVoter.AlreadyVotedOrDeposited.selector);
        voter.depositManaged(1, 2);
    }

    function testCannotDepositManagedWithExpiredNft() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 1 weeks);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skip(2 weeks + 1 hours + 1);

        vm.expectRevert(IVotingEscrow.ZeroBalance.selector);
        voter.depositManaged(tokenId, mTokenId);
    }

    function testCannotWithdrawManagedIfNotLocked() public {
        skipAndRoll(1 hours);
        escrow.createManagedLockFor(address(owner));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.InvalidManagedNFTId.selector);
        voter.withdrawManaged(tokenId);
    }

    function testCannotWithdrawManagedIfNotVoter() public {
        skipAndRoll(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        escrow.createManagedLockFor(address(owner));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(1);

        vm.expectRevert(IVotingEscrow.NotVoter.selector);
        escrow.withdrawManaged(tokenId);
    }

    function testCannotWithdrawManagedUntilAfterDistributeWindow() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2)); // 1

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME); // 2
        assertEq(escrow.locked(tokenId).end, 126403200);

        skipAndRoll(1 hours);
        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(0);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.withdrawManaged(tokenId);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.withdrawManaged(tokenId);

        skip(30 minutes);
        vm.expectRevert(IVoter.DistributeWindow.selector);
        voter.withdrawManaged(tokenId);

        skip(1);
        voter.withdrawManaged(tokenId);
    }

    function testWithdrawManagedWithFlashProtection() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        // deposit two normal veNFTS
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        voter.depositManaged(tokenId2, mTokenId);

        skipToNextEpoch(2 hours);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        vm.startPrank(address(owner2));
        voter.vote(mTokenId, pools, weights);
        assertEq(voter.totalWeight(), TOKEN_1 * 2);

        skipAndRoll(1);

        // Same block transfer/withdrawManaged
        escrow.transferFrom(address(owner2), address(owner3), mTokenId);
        vm.stopPrank();
        voter.withdrawManaged(tokenId2);

        // properly synced with voting balance
        assertEq(voter.totalWeight(), TOKEN_1);
    }

    function testDepositManagedWithFlashProtection() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(2 hours);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        vm.startPrank(address(owner2));
        voter.vote(mTokenId, pools, weights);

        // Same block transfer/depositManaged
        assertEq(voter.totalWeight(), TOKEN_1);
        escrow.transferFrom(address(owner2), address(owner3), mTokenId);
        vm.stopPrank();
        voter.depositManaged(tokenId2, mTokenId);

        // properly synced with voting balance
        assertEq(voter.totalWeight(), TOKEN_1 * 2);
    }

    function testWithdrawManagedResetsLastVotedOnce() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);

        skipToNextEpoch(2 hours);

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        vm.prank(address(owner2));
        voter.vote(mTokenId, pools, weights);

        // The only locked veNFT withdraws - resetting the voting power and lastVoted
        assertEq(voter.totalWeight(), TOKEN_1);
        assertEq(voter.lastVoted(mTokenId), block.timestamp);
        voter.withdrawManaged(tokenId);
        assertEq(voter.totalWeight(), 0);
        assertEq(voter.lastVoted(mTokenId), 0);

        // The same veNFT can deposit back and managed veNFT can re-vote
        voter.depositManaged(tokenId, mTokenId);
        vm.prank(address(owner2));
        voter.vote(mTokenId, pools, weights);
        assertEq(voter.totalWeight(), TOKEN_1);
        assertEq(voter.lastVoted(mTokenId), block.timestamp);
        // veNFT cannot withdraw until next epoch
        vm.expectRevert(IVoter.AlreadyVotedOrDeposited.selector);
        voter.withdrawManaged(tokenId);

        skipToNextEpoch(2 hours);
        vm.prank(address(owner2));
        voter.vote(mTokenId, pools, weights);

        // The only locked veNFT withdraws - resetting the voting power and lastVoted
        assertEq(voter.totalWeight(), TOKEN_1);
        assertEq(voter.lastVoted(mTokenId), block.timestamp);
        voter.withdrawManaged(tokenId);
        assertEq(voter.totalWeight(), 0);
        assertEq(voter.lastVoted(mTokenId), 0);

        // A new veNFT can deposit back and managed veNFT can re-vote
        voter.depositManaged(tokenId2, mTokenId);
        vm.prank(address(owner2));
        voter.vote(mTokenId, pools, weights);
        assertEq(voter.totalWeight(), TOKEN_1);
        assertEq(voter.lastVoted(mTokenId), block.timestamp);
        // veNFT cannot withdraw until next epoch
        vm.expectRevert(IVoter.AlreadyVotedOrDeposited.selector);
        voter.withdrawManaged(tokenId2);
    }

    function testWithdrawManagedWithZeroReward() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 supply = escrow.supply();

        skipAndRoll(2 weeks);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit WithdrawManaged(address(owner), tokenId, mTokenId, TOKEN_1, 1818001);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        voter.withdrawManaged(tokenId);

        IVotingEscrow.LockedBalance memory locked;

        /// on withdraw, re-lock for max-lock time rounded down by week
        // start time: 126403200
        // lock time = start time + two epochs = 126403200 + 604800 * 2 = 127612800
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127612800);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(127612800), -7927447995);

        // check withdrawing user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 997231727113978005); // (TOKEN_1 / MAXTIME) * (127612800 - 1818001)
        assertEq(convert(userPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        locked = escrow.locked(mTokenId);
        assertEq(uint256(uint128(locked.amount)), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point updates correctly
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 4);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(4);
        assertEq(convert(globalPoint.bias), 997231727113978005);
        assertEq(convert(globalPoint.slope), 7927447995);
        assertEq(globalPoint.ts, 1818001);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);

        // check voting checkpoints
        assertEq(escrow.numCheckpoints(mTokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(mTokenId, 0);
        assertEq(checkpoint.fromTimestamp, 608401);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.balanceOfNFT(mTokenId), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 997231727113978005);
        assertEq(escrow.idToManaged(tokenId), 0);
        assertEq(escrow.weights(tokenId, mTokenId), 0);
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), 997231727113978005);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.NORMAL));

        // check withdrawal represented in locked / free managed rewards
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(lockedManagedReward.balanceOf(tokenId), 0);
        assertEq(lockedManagedReward.totalSupply(), 0);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(freeManagedReward.balanceOf(tokenId), 0);
        assertEq(freeManagedReward.totalSupply(), 0);
    }

    function testWithdrawManagedWithLockedReward() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);

        // locked rewards initially empty
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(AERO.balanceOf(address(freeManagedReward)), 0);

        // simulate locked rewards (i.e. rebase / compound) via increaseAmount
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        vm.stopPrank();

        // check user point updates correctly on increaseAmount
        assertEq(escrow.userPointEpoch(mTokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(mTokenId, 1);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 608401);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, TOKEN_1 * 2);

        // check global point updates correctly on increaseAmount
        assertEq(escrow.epoch(), 1);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(1);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 608401);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 2);
        assertEq(escrow.balanceOfNFT(mTokenId), TOKEN_1 * 2);

        assertEq(escrow.supply(), TOKEN_1 * 2);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), TOKEN_1);
        assertEq(lockedManagedReward.tokenRewardsPerEpoch(address(AERO), 604800), TOKEN_1);

        skipAndRoll(2 weeks);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit WithdrawManaged(address(owner), tokenId, mTokenId, TOKEN_1 * 2, 1818001);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        voter.withdrawManaged(tokenId);

        IVotingEscrow.LockedBalance memory locked;

        /// on withdraw, re-lock for max-lock time rounded down by week
        // start time: 126403200
        // lock time = start time + two epochs = 126403200 + 604800 * 2 = 127612800
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 127612800);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(127612800), -15854895991);

        // check withdrawing user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 1994463454353750809); // (TOKEN_1 / MAXTIME) * (127612800 - 1818001)
        assertEq(convert(userPoint.slope), 15854895991); // TOKEN_1 * 2 / MAXTIME
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        locked = escrow.locked(mTokenId);
        assertLt(uint256(uint128(locked.amount)), 1e6);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point updates correctly
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 4);
        globalPoint = escrow.pointHistory(4);
        assertEq(convert(globalPoint.bias), 1994463454353750809);
        assertEq(convert(globalPoint.slope), 15854895991);
        assertEq(globalPoint.ts, 1818001);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);

        // check voting checkpoints
        assertEq(escrow.numCheckpoints(mTokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(mTokenId, 0);
        assertEq(checkpoint.fromTimestamp, 608401);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.balanceOfNFT(mTokenId), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 1994463454353750809);
        assertEq(escrow.idToManaged(tokenId), 0);
        assertEq(escrow.weights(tokenId, mTokenId), 0);
        assertEq(escrow.supply(), TOKEN_1 * 2);
        assertEq(escrow.totalSupply(), 1994463454353750809);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.NORMAL));

        // check withdrawal represented in locked managed rewards
        assertEq(lockedManagedReward.balanceOf(tokenId), 0);
        assertEq(lockedManagedReward.totalSupply(), 0);
        assertEq(freeManagedReward.balanceOf(tokenId), 0);
        assertEq(freeManagedReward.totalSupply(), 0);

        assertEq(AERO.balanceOf(address(escrow)), TOKEN_1 * 2);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);
    }

    function testWithdrawManagedWithFreeReward() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        uint256 supply = escrow.supply();

        // locked rewards initially empty
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(AERO.balanceOf(address(freeManagedReward)), 0);

        // simulate free rewards via notifyRewardAmount
        AERO.approve(address(freeManagedReward), TOKEN_1);
        freeManagedReward.notifyRewardAmount(address(AERO), TOKEN_1);

        assertEq(escrow.supply(), supply);
        assertEq(AERO.balanceOf(address(freeManagedReward)), TOKEN_1);
        assertEq(freeManagedReward.tokenRewardsPerEpoch(address(AERO), 604800), TOKEN_1);

        skipAndRoll(2 weeks);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit WithdrawManaged(address(owner), tokenId, mTokenId, TOKEN_1, 1818001);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        voter.withdrawManaged(tokenId);

        IVotingEscrow.LockedBalance memory locked;

        /// on withdraw, re-lock for max-lock time rounded down by week
        // start time: 126403200
        // lock time = start time + two epochs = 126403200 + 604800 * 2 = 127612800
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1);
        assertEq(locked.end, 127612800);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(127612800), -7927447995);

        // check withdrawing user point updates correctly
        // create lock and deposit at same ts, withdraw in different ts
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 997231727113978005); // (TOKEN_1 / MAXTIME) * (127612800 - 1818001)
        assertEq(convert(userPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        locked = escrow.locked(mTokenId);
        assertLt(uint256(uint128(locked.amount)), 1e6);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point updates correctly
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 4);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(4);
        assertEq(convert(globalPoint.bias), 997231727113978005);
        assertEq(convert(globalPoint.slope), 7927447995);
        assertEq(globalPoint.ts, 1818001);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);

        // check voting checkpoints
        assertEq(escrow.numCheckpoints(mTokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(mTokenId, 0);
        assertEq(checkpoint.fromTimestamp, 608401);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        assertEq(escrow.balanceOfNFT(mTokenId), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 997231727113978005);
        assertEq(escrow.idToManaged(tokenId), 0);
        assertEq(escrow.weights(tokenId, mTokenId), 0);
        assertEq(escrow.supply(), supply);
        assertEq(escrow.totalSupply(), 997231727113978005);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.NORMAL));
        // check withdrawal represented in locked managed rewards
        assertEq(lockedManagedReward.balanceOf(tokenId), 0);
        assertEq(lockedManagedReward.totalSupply(), 0);
        assertEq(freeManagedReward.balanceOf(tokenId), 0);
        assertEq(freeManagedReward.totalSupply(), 0);

        assertEq(AERO.balanceOf(address(escrow)), TOKEN_1);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);

        skip(1 hours);
        // collect reward after withdrawal
        address[] memory rewards = new address[](1);
        rewards[0] = address(AERO);
        uint256 pre = AERO.balanceOf(address(owner));
        freeManagedReward.getReward(tokenId, rewards);
        uint256 post = AERO.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testWithdrawManagedWithLockedRewardWithDelegatingManagedNFT() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        vm.prank(address(owner2));
        escrow.delegate(mTokenId, tokenId2);
        voter.depositManaged(tokenId, mTokenId);

        // locked rewards initially empty
        lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);
        freeManagedReward = FreeManagedReward(escrow.managedToFree(mTokenId));
        assertEq(AERO.balanceOf(address(freeManagedReward)), 0);

        // simulate locked rewards (i.e. rebase / compound) via increaseAmount
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(mTokenId, TOKEN_1);
        vm.stopPrank();

        // check user point updates correctly on increaseAmount
        assertEq(escrow.userPointEpoch(mTokenId), 1);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(mTokenId, 1);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 608401);
        assertEq(userPoint.blk, 1);
        assertEq(userPoint.permanent, TOKEN_1 * 2);

        // check global point updates correctly on increaseAmount
        assertEq(escrow.epoch(), 1);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(1);
        assertEq(convert(globalPoint.bias), 997231727113978005); // (TOKEN_1 / MAXTIME) * (126403200 - 608401)
        assertEq(convert(globalPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(globalPoint.ts, 608401);
        assertEq(globalPoint.blk, 1);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 2);
        assertEq(escrow.balanceOfNFT(mTokenId), TOKEN_1 * 2);

        assertEq(escrow.supply(), TOKEN_1 * 3);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), TOKEN_1);
        assertEq(lockedManagedReward.tokenRewardsPerEpoch(address(AERO), 604800), TOKEN_1);

        skipAndRoll(2 weeks);
        vm.expectEmit(true, false, false, false, address(escrow));
        emit WithdrawManaged(address(owner), tokenId, mTokenId, TOKEN_1, 1818001);
        voter.withdrawManaged(tokenId);

        IVotingEscrow.LockedBalance memory locked;

        /// on withdraw, re-lock for max-lock time rounded down by week
        // start time: 126403200
        // lock time = start time + two epochs = 126403200 + 604800 * 2 = 127612800
        locked = escrow.locked(tokenId);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 2);
        assertEq(locked.end, 127612800);
        assertEq(locked.isPermanent, false);
        assertEq(escrow.slopeChanges(127612800), -15854895991);

        // check withdrawing user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 1994463454353750809);
        assertEq(convert(userPoint.slope), 15854895991);
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        locked = escrow.locked(mTokenId);
        assertLt(uint256(uint128(locked.amount)), 1e6);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check managed nft user point updates correctly
        assertEq(escrow.userPointEpoch(mTokenId), 2);
        userPoint = escrow.userPointHistory(mTokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 1818001);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 4);
        globalPoint = escrow.pointHistory(4);
        assertEq(convert(globalPoint.bias), 2982106140372976814); // tokenId + tokenId2 bias
        assertEq(convert(globalPoint.slope), 23782343986);
        assertEq(globalPoint.ts, 1818001);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);

        // check voting checkpoints
        assertEq(escrow.numCheckpoints(mTokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(mTokenId, 0);
        assertEq(checkpoint.fromTimestamp, 608401);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 3);

        // check mTokenId delegatee delegatedBalance reduced
        assertEq(escrow.numCheckpoints(tokenId2), 2);
        checkpoint = escrow.checkpoints(tokenId2, 1);
        assertEq(checkpoint.fromTimestamp, 1818001);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId2, 1818001), 987642686019226005);
        assertEq(escrow.balanceOfNFTAt(tokenId2, 1818000), 987642693946674000);
        assertEq(escrow.getPastVotes(address(owner), tokenId2, 1818000), TOKEN_1 * 2 + 987642693946674000);

        assertEq(escrow.balanceOfNFT(mTokenId), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 1994463454353750809);
        assertEq(escrow.idToManaged(tokenId), 0);
        assertEq(escrow.weights(tokenId, mTokenId), 0);
        assertEq(escrow.supply(), TOKEN_1 * 3);
        assertEq(escrow.totalSupply(), 2982106140372976814);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.NORMAL));

        // check withdrawal represented in locked managed rewards
        assertEq(lockedManagedReward.balanceOf(tokenId), 0);
        assertEq(lockedManagedReward.totalSupply(), 0);
        assertEq(freeManagedReward.balanceOf(tokenId), 0);
        assertEq(freeManagedReward.totalSupply(), 0);

        assertEq(AERO.balanceOf(address(escrow)), TOKEN_1 * 3);
        assertEq(AERO.balanceOf(address(lockedManagedReward)), 0);
    }

    function testCannotIncreaseAmountWithLockedNft() public {
        skipAndRoll(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotManagedOrNormalNFT.selector);
        escrow.increaseAmount(tokenId, TOKEN_1);
    }

    function testCannotIncreaseAmountWithManagedNftWithNoBalance() public {
        skipAndRoll(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        AERO.approve(address(escrow), type(uint256).max);

        vm.expectRevert(IVotingEscrow.NoLockFound.selector);
        escrow.increaseAmount(mTokenId, TOKEN_1);
    }

    function testCannotIncreaseUnlockTimeWithLockedNft() public {
        skipAndRoll(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.increaseUnlockTime(tokenId, MAXTIME);
    }

    function testCannotWithdrawLockedVeNft() public {
        skipAndRoll(1 hours);
        // lock for four weeks
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 * 7 * 86400);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        skip(8 weeks);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.withdraw(tokenId);
    }

    function testCannotMergeFromLockedNft() public {
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.merge(tokenId, tokenId2);
    }

    function testCannotMergeToLockedNft() public {
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.merge(tokenId2, tokenId);
    }

    function testCannotTransferLockedVeNft() public {
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotManagedOrNormalNFT.selector);
        escrow.transferFrom(address(this), address(owner2), tokenId);
    }

    function testCannotMergeFromManagedNft() public {
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.merge(mTokenId, tokenId2);
    }

    function testCannotMergeToManagedNft() public {
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.merge(tokenId2, mTokenId);
    }

    function testTransferManagedNft() public {
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        skip(1 hours);

        escrow.transferFrom(address(owner), address(owner2), mTokenId);

        assertEq(escrow.ownerOf(mTokenId), address(owner2));
    }

    function testCannotWithdrawManagedNft() public {
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 * 7 * 86400);

        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        voter.depositManaged(tokenId, mTokenId);

        skip(400 weeks);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.withdraw(mTokenId);
    }

    function testCreateManagedLockForAccessControl() public {
        address allowedManager = escrow.allowedManager();
        assertEq(voter.governor(), address(governor));
        assertEq(allowedManager, address(owner));

        uint256 mTokenId;
        // governor can create managed veNFT - no revert
        vm.prank(address(governor));
        mTokenId = escrow.createManagedLockFor(address(owner3));
        assertEq(mTokenId, 1);
        // owner2 cannot create managed veNFT
        vm.expectRevert(IVotingEscrow.NotGovernorOrManager.selector);
        vm.prank(address(owner2));
        escrow.createManagedLockFor(address(owner3));

        // change the allowedManager
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner2));

        // now both governor and owner2 (aka allowedManager) can create managed veNFTs
        vm.prank(address(governor));
        mTokenId = escrow.createManagedLockFor(address(owner3));
        assertEq(mTokenId, 2);
        vm.prank(address(owner2));
        mTokenId = escrow.createManagedLockFor(address(owner3));
        assertEq(mTokenId, 3);
        // only governor / owner2 have access
        vm.expectRevert(IVotingEscrow.NotGovernorOrManager.selector);
        vm.prank(address(owner3));
        escrow.createManagedLockFor(address(owner3));
    }

    function testCannotSetAllowedManagerWithSameAddress() public {
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner2));

        assertEq(escrow.allowedManager(), address(owner2));

        vm.prank(address(governor));
        vm.expectRevert(IVotingEscrow.SameAddress.selector);
        escrow.setAllowedManager(address(owner2));
    }

    function testCannotSetAllowedManagerToZeroAddress() public {
        vm.prank(address(governor));
        vm.expectRevert(IVotingEscrow.ZeroAddress.selector);
        escrow.setAllowedManager(address(0));
    }

    function testSetAllowedManager() public {
        assertEq(escrow.allowedManager(), address(owner));
        // Voter.governor can change the allowedManager to a new address
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner2));
        assertEq(escrow.allowedManager(), address(owner2));

        // new address does not have permissions to modify the allowedManager
        vm.expectRevert(IVotingEscrow.NotGovernor.selector);
        vm.prank(address(owner2));
        escrow.setAllowedManager(address(owner3));

        // governor can still change the allowedManager
        vm.prank(address(governor));
        escrow.setAllowedManager(address(owner3));
        assertEq(escrow.allowedManager(), address(owner3));
    }

    function testCannotSetManagedStateWithSameState() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        vm.expectRevert(IVotingEscrow.SameState.selector);
        escrow.setManagedState(mTokenId, false);
    }

    function testCannotSetManagedStateWithNotManagedNFT() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.NotManagedNFT.selector);
        escrow.setManagedState(tokenId, false);
    }

    function testCannotSetManagedStateIfNotEmergencyCouncilOrGovernor() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        vm.expectRevert(IVotingEscrow.NotEmergencyCouncilOrGovernor.selector);
        vm.prank(address(owner2));
        escrow.setManagedState(mTokenId, false);
    }

    function testSetManagedStateWithEmergencyCouncil() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        assertFalse(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        escrow.setManagedState(mTokenId, true);
        assertTrue(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        escrow.setManagedState(mTokenId, false);
        assertFalse(escrow.deactivated(mTokenId));
    }

    function testSetManagedStateWithGovernor() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        assertFalse(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        vm.prank(address(governor));
        escrow.setManagedState(mTokenId, true);
        assertTrue(escrow.deactivated(mTokenId));

        skipAndRoll(1);

        vm.prank(address(governor));
        escrow.setManagedState(mTokenId, false);
        assertFalse(escrow.deactivated(mTokenId));
    }
}
