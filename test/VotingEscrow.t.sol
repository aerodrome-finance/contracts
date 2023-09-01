// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

contract VotingEscrowTest is BaseTest {
    event DelegateChanged(address indexed delegator, uint256 indexed fromDelegate, uint256 indexed toDelegate);
    event LockPermanent(address indexed _owner, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
    event UnlockPermanent(address indexed _owner, uint256 indexed _tokenId, uint256 amount, uint256 _ts);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event Merge(
        address indexed _sender,
        uint256 indexed _from,
        uint256 indexed _to,
        uint256 _amountFrom,
        uint256 _amountTo,
        uint256 _amountFinal,
        uint256 _locktime,
        uint256 _ts
    );
    event MetadataUpdate(uint256 _tokenId);
    event NotifyReward(address indexed from, address indexed reward, uint256 indexed epoch, uint256 amount);
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId1,
        uint256 indexed _tokenId2,
        address _sender,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _locktime,
        uint256 _ts
    );

    function testInitialState() public {
        assertEq(escrow.team(), address(owner));
        assertEq(escrow.allowedManager(), address(owner));
        // voter should already have been setup
        assertEq(escrow.voter(), address(voter));
    }

    function testSupportInterfaces() public {
        assertTrue(escrow.supportsInterface(type(IERC165).interfaceId));
        assertTrue(escrow.supportsInterface(type(IERC721).interfaceId));
        assertTrue(escrow.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(escrow.supportsInterface(0x49064906)); // 4906 is events only, so uses a custom interface id
        assertTrue(escrow.supportsInterface(type(IERC6372).interfaceId));
    }

    function testCannotDepositForWithLockedNFT() public {
        skipAndRoll(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);
        assertEq(uint256(escrow.escrowType(tokenId)), uint256(IVotingEscrow.EscrowType.LOCKED));

        vm.expectRevert(IVotingEscrow.NotManagedOrNormalNFT.selector);
        escrow.depositFor(tokenId, TOKEN_1);
    }

    function testCannotDepositForWithManagedNFTIfNotDistributor() public {
        skipAndRoll(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotDistributor.selector);
        escrow.depositFor(mTokenId, TOKEN_1);
    }

    function testDepositForWithManagedNFT() public {
        skipAndRoll(1 hours);
        uint256 reward = TOKEN_1;
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));
        LockedManagedReward lockedManagedReward = LockedManagedReward(escrow.managedToLocked(mTokenId));
        assertEq(AERO.allowance(address(escrow), address(lockedManagedReward)), 0);

        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        deal(address(AERO), address(distributor), TOKEN_1);

        uint256 pre = AERO.balanceOf(address(lockedManagedReward));
        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(mTokenId);
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true, address(lockedManagedReward));
        emit NotifyReward(address(escrow), address(AERO), 604800, reward);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(mTokenId);
        escrow.depositFor(mTokenId, reward);
        uint256 post = AERO.balanceOf(address(lockedManagedReward));
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(mTokenId);

        assertEq(uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end)));
        assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), reward);
        assertEq(post - pre, reward);
        assertEq(AERO.allowance(address(escrow), address(lockedManagedReward)), 0);
    }

    function testDepositFor() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        AERO.approve(address(escrow), TOKEN_1);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.depositFor(tokenId, TOKEN_1);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);

        assertEq(uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end)));
        assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), TOKEN_1);
    }

    function testIncreaseAmount() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        AERO.approve(address(escrow), TOKEN_1);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.increaseAmount(tokenId, TOKEN_1);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);

        assertEq(uint256(uint128(postLocked.end)), uint256(uint128(preLocked.end)));
        assertEq(uint256(uint128(postLocked.amount)) - uint256(uint128(preLocked.amount)), TOKEN_1);
    }

    function testIncreaseUnlockTime() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 weeks);

        skip((1 weeks) / 2);

        IVotingEscrow.LockedBalance memory preLocked = escrow.locked(tokenId);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.increaseUnlockTime(tokenId, MAXTIME);
        IVotingEscrow.LockedBalance memory postLocked = escrow.locked(tokenId);

        uint256 expectedLockTime = ((block.timestamp + MAXTIME) / WEEK) * WEEK;
        assertEq(uint256(uint128(postLocked.end)), expectedLockTime);
        assertEq(uint256(uint128(postLocked.amount)), uint256(uint128(preLocked.amount)));
    }

    function testCreateLock() public {
        AERO.approve(address(escrow), 1e25);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week

        // Balance should be zero before and 1 after creating the lock
        assertEq(escrow.balanceOf(address(owner)), 0);
        escrow.createLock(1e25, lockDuration);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(uint256(escrow.escrowType(1)), uint256(IVotingEscrow.EscrowType.NORMAL));
        assertEq(escrow.numCheckpoints(1), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner), 1, block.timestamp), 47945126204972095225334);
        assertEq(escrow.balanceOfNFT(1), 47945126204972095225334);
    }

    function testCreateLockOutsideAllowedZones() public {
        AERO.approve(address(escrow), 1e25);
        vm.expectRevert(IVotingEscrow.LockDurationTooLong.selector);
        escrow.createLock(1e21, MAXTIME + 1 weeks);
    }

    function testIncreaseAmountWithNormalLock() public {
        // timestamp: 604801
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1);

        AERO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1 * 2);
        assertEq(locked.end, 126403200);
        assertEq(locked.isPermanent, false);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 1994520516124422418); // (TOKEN_1 * 2 / MAXTIME) * (126403200 - 604802)
        assertEq(convert(userPoint.slope), 15854895991); // TOKEN_1 * 2 / MAXTIME
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 1994520516124422418);
        assertEq(convert(globalPoint.slope), 15854895991);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.supply(), TOKEN_1 * 2);
        assertEq(escrow.slopeChanges(126403200), -15854895991);
    }

    function testIncreaseAmountWithPermanentLock() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1);

        AERO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1 * 2);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1 * 2);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 2);
        assertEq(escrow.supply(), TOKEN_1 * 2);

        // no delegation checkpoint created
        assertEq(escrow.numCheckpoints(tokenId), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(tokenId, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId, 604802), TOKEN_1 * 2);
        assertEq(escrow.balanceOfNFT(tokenId), TOKEN_1 * 2);
        assertEq(escrow.totalSupply(), TOKEN_1 * 2);
    }

    function testIncreaseAmountWithDelegatedPermanentLock() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        skipAndRoll(1);
        escrow.delegate(tokenId, tokenId2);

        // check delegation checkpoint created for delegator
        assertEq(escrow.delegates(tokenId), tokenId2);
        assertEq(escrow.numCheckpoints(tokenId), 2);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(tokenId, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId2);
        assertEq(escrow.getPastVotes(address(owner), tokenId, 604802), 0);
        assertEq(escrow.balanceOfNFT(tokenId), TOKEN_1 * 1);

        skipAndRoll(1);
        AERO.approve(address(escrow), TOKEN_1);
        escrow.increaseAmount(tokenId, TOKEN_1);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1 * 2);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604803);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, TOKEN_1 * 2);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 997260250071864015); // (TOKEN_1 / MAXTIME) * (126403200 - 604803)
        assertEq(convert(globalPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(globalPoint.ts, 604803);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 2);

        // no new checkpoints for delegator as nothing changes delegation-wise
        assertEq(escrow.delegates(tokenId), tokenId2);
        assertEq(escrow.numCheckpoints(tokenId), 2);
        checkpoint = escrow.checkpoints(tokenId, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, tokenId2);
        assertEq(escrow.getPastVotes(address(owner), tokenId, 604803), 0);
        assertEq(escrow.balanceOfNFT(tokenId), TOKEN_1 * 2);

        // delegatee balance updates
        assertEq(escrow.numCheckpoints(tokenId2), 3);
        checkpoint = escrow.checkpoints(tokenId2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1 * 2);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner2), tokenId2, 604803), TOKEN_1 * 2 + 997260250071864015);
        assertEq(escrow.balanceOfNFT(tokenId2), 997260250071864015);
        assertEq(escrow.totalSupply(), TOKEN_1 * 2 + 997260250071864015);
        assertEq(escrow.supply(), TOKEN_1 * 3);
    }

    function testCannotIncreaseUnlockTimeWithPermanentLock() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.PermanentLock.selector);
        escrow.increaseUnlockTime(tokenId, MAXTIME);
    }

    function testCannotIncreaseUnlockTimeWithManagedNFT() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner2));

        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        voter.depositManaged(tokenId, mTokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.increaseUnlockTime(tokenId, MAXTIME);
    }

    function testTransferFrom() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1);

        // check tokenId checkpoint
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 1);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        escrow.transferFrom(address(owner), address(owner2), tokenId);

        assertEq(escrow.balanceOf(address(owner)), 0);
        // assertEq(escrow.ownerToNFTokenIdList(address(owner), 0), 0);
        assertEq(escrow.ownerOf(tokenId), address(owner2));
        assertEq(escrow.balanceOf(address(owner2)), 1);
        // assertEq(escrow.ownerToNFTokenIdList(address(owner2), 0), tokenId);

        // check new checkpoint created for tokenId with updated owner
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 2);
        checkpoint = escrow.checkpoints(1, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // flash protection
        assertEq(escrow.balanceOfNFT(1), 0);
    }

    function testTransferFromWithDelegatedFrom() public {
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(1);
        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        skipAndRoll(1);
        escrow.delegate(1, 2);
        skipAndRoll(1);

        escrow.transferFrom(address(owner), address(owner2), 1);

        // check new checkpoint created for tokenId with updated owner
        assertEq(escrow.numCheckpoints(1), 3);
        assertEq(escrow.delegates(1), 0);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(1, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check dedelegation occurs prior to transfer
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 3);
        checkpoint = escrow.checkpoints(2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
    }

    function testBurnFromApproved() public {
        AERO.approve(address(escrow), 1e25);
        uint256 tokenId = escrow.createLock(1e21, MAXTIME);
        skipAndRoll(MAXTIME + 1);
        escrow.approve(address(owner2), tokenId);
        vm.prank(address(owner2));
        // should not revert
        escrow.withdraw(tokenId);
    }

    function testCannotWithdrawPermanentLock() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.PermanentLock.selector);
        escrow.withdraw(tokenId);
    }

    function testCannotWithdrawBeforeLockExpiry() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        uint256 tokenId = escrow.createLock(TOKEN_1, lockDuration);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.LockNotExpired.selector);
        escrow.withdraw(tokenId);
    }

    function testWithdraw() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.createLock(TOKEN_1, lockDuration);
        uint256 preBalance = AERO.balanceOf(address(owner));

        skipAndRoll(lockDuration);
        escrow.withdraw(1);

        uint256 postBalance = AERO.balanceOf(address(owner));
        assertEq(postBalance - preBalance, TOKEN_1);
        assertEq(escrow.ownerOf(1), address(0));
        assertEq(escrow.balanceOf(address(owner)), 0);
        // assertEq(escrow.ownerToNFTokenIdList(address(owner), 0), 0);

        // check voting checkpoint created on burn updating owner
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 2);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(1, 1);
        assertEq(checkpoint.fromTimestamp, 1209601);
        assertEq(checkpoint.owner, address(0));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner), 1, block.timestamp), 0);
        assertEq(escrow.balanceOfNFT(1), 0);
    }

    function testCheckTokenURICalls() public {
        // tokenURI should not work for non-existent token ids
        vm.expectRevert(IVotingEscrow.NonExistentToken.selector);
        escrow.tokenURI(999);
        AERO.approve(address(escrow), 1e25);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.createLock(1e25, lockDuration);

        uint256 tokenId = 1;
        skip(lockDuration);
        vm.roll(block.number + 1); // mine the next block

        // Just check that this doesn't revert
        escrow.tokenURI(tokenId);

        // Withdraw, which destroys the NFT
        escrow.withdraw(tokenId);

        // tokenURI should not work for this anymore as the NFT is burnt
        vm.expectRevert(IVotingEscrow.NonExistentToken.selector);
        escrow.tokenURI(tokenId);
    }

    function testConfirmSupportsInterfaceWorksWithAssertedInterfaces() public {
        // Check that it supports all the asserted interfaces.
        bytes4 ERC165_INTERFACE_ID = 0x01ffc9a7;
        bytes4 ERC721_INTERFACE_ID = 0x80ac58cd;
        bytes4 ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

        assertTrue(escrow.supportsInterface(ERC165_INTERFACE_ID));
        assertTrue(escrow.supportsInterface(ERC721_INTERFACE_ID));
        assertTrue(escrow.supportsInterface(ERC721_METADATA_INTERFACE_ID));
    }

    function testCheckSupportsInterfaceHandlesUnsupportedInterfacesCorrectly() public {
        bytes4 ERC721_FAKE = 0x780e9d61;
        assertFalse(escrow.supportsInterface(ERC721_FAKE));
    }

    function testCannotMergeSameVeNFT() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.SameNFT.selector);
        escrow.merge(tokenId, tokenId);
    }

    function testCannotMergeFromVeNFTWithNoApprovalOrOwnership() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 owner2TokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        escrow.merge(owner2TokenId, ownerTokenId);
    }

    function testCannotMergeToVeNFTWithNoApprovalOrOwnership() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 owner2TokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        escrow.merge(ownerTokenId, owner2TokenId);
    }

    function testCannotMergeAlreadyVotedFromVeNFT() public {
        skip(1 hours);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        skip(1);

        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(tokenId, pools, weights);

        skip(1);

        vm.expectRevert(IVotingEscrow.AlreadyVoted.selector);
        escrow.merge(tokenId, tokenId2);
    }

    function testMergeWithFromLockTimeGreaterThanToLockTime() public {
        // first veNFT max lock time (4yrs)
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 yr lock time
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 365 days);

        uint256 aeroSupply = escrow.supply();
        uint256 expectedLockTime = escrow.locked(tokenId).end;
        skip(1);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit Merge(address(owner), tokenId, tokenId2, TOKEN_1, TOKEN_1, TOKEN_1 * 2, expectedLockTime, 604802);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId2);
        escrow.merge(tokenId, tokenId2);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(0));
        assertEq(escrow.ownerOf(tokenId2), address(owner));
        assertEq(escrow.supply(), aeroSupply);

        IVotingEscrow.UserPoint memory pt = escrow.userPointHistory(tokenId, 2);
        assertEq(uint256(int256(pt.bias)), 0);
        assertEq(uint256(int256(pt.slope)), 0);
        assertEq(pt.ts, 604802);
        assertEq(pt.blk, 1);

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.UserPoint memory pt2 = escrow.userPointHistory(tokenId2, 2);
        uint256 slope = (TOKEN_1 * 2) / MAXTIME;
        uint256 bias = slope * (expectedLockTime - block.timestamp);
        assertEq(uint256(int256(pt2.bias)), bias);
        assertEq(uint256(int256(pt2.slope)), slope);
        assertEq(pt2.ts, 604802);
        assertEq(pt2.blk, 1);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId2);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
    }

    function testMergeWithToLockTimeGreaterThanFromLockTime() public {
        // first veNFT max lock time (4yrs)
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 yr lock time
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 365 days);

        uint256 aeroSupply = escrow.supply();
        uint256 expectedLockTime = escrow.locked(tokenId).end;

        skip(1);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit Merge(address(owner), tokenId2, tokenId, TOKEN_1, TOKEN_1, TOKEN_1 * 2, expectedLockTime, 604802);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.merge(tokenId2, tokenId);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.ownerOf(tokenId2), address(0));
        assertEq(escrow.supply(), aeroSupply);

        IVotingEscrow.UserPoint memory pt2 = escrow.userPointHistory(tokenId2, 2);
        assertEq(uint256(int256(pt2.bias)), 0);
        assertEq(uint256(int256(pt2.slope)), 0);
        assertEq(pt2.ts, 604802);
        assertEq(pt2.blk, 1);

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId2);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.UserPoint memory pt = escrow.userPointHistory(tokenId, 2);
        uint256 slope = (TOKEN_1 * 2) / MAXTIME;
        uint256 bias = slope * (expectedLockTime - block.timestamp);
        assertEq(uint256(int256(pt.bias)), bias);
        assertEq(uint256(int256(pt.slope)), slope);
        assertEq(pt.ts, 604802);
        assertEq(pt.blk, 1);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
    }

    function testMergeWithPermanentTo() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.slopeChanges(126403200), -7927447995);
        uint256 tokenId2 = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        escrow.lockPermanent(tokenId2);

        skipAndRoll(1);

        escrow.merge(tokenId, tokenId2);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(0));
        assertEq(escrow.ownerOf(tokenId2), address(owner));
        assertEq(escrow.supply(), TOKEN_1 * 3);

        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(locked.amount, 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 3);
        assertEq(uint256(uint128(locked.end)), 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId2), 2);
        userPoint = escrow.userPointHistory(tokenId2, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1 * 3);

        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 3);

        assertEq(escrow.slopeChanges(126403200), 0);
        assertEq(escrow.permanentLockBalance(), TOKEN_1 * 3);
    }

    function testMergeWithDelegatedPermanentTo() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1 * 2, MAXTIME);
        escrow.lockPermanent(tokenId2);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId3 = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        escrow.delegate(tokenId2, tokenId3);
        skipAndRoll(1);

        assertEq(escrow.numCheckpoints(tokenId), 1);
        assertEq(escrow.numCheckpoints(tokenId2), 1);

        escrow.merge(tokenId, tokenId2);

        // check from user points
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(locked.amount, 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check to user points
        locked = escrow.locked(tokenId2);
        assertEq(uint256(uint128(locked.amount)), TOKEN_1 * 3);
        assertEq(uint256(uint128(locked.end)), 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(tokenId2), 2);
        userPoint = escrow.userPointHistory(tokenId2, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1 * 3);

        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 997260257999312010); // contribution from tokenId3
        assertEq(convert(globalPoint.slope), 7927447995);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1 * 3);

        // from delegate checkpoint created
        assertEq(escrow.delegates(tokenId), 0);
        assertEq(escrow.numCheckpoints(tokenId), 2);
        IVotingEscrow.Checkpoint memory checkpoints = escrow.checkpoints(tokenId, 1);
        assertEq(checkpoints.fromTimestamp, 604802);
        assertEq(checkpoints.owner, address(0));
        assertEq(checkpoints.delegatedBalance, 0);
        assertEq(checkpoints.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner), tokenId, 604802), 0);
        assertEq(escrow.balanceOfNFT(tokenId), 0);

        // to delegate checkpoint unchanged
        assertEq(escrow.delegates(tokenId2), tokenId3);
        assertEq(escrow.numCheckpoints(tokenId2), 1);
        checkpoints = escrow.checkpoints(tokenId2, 0);
        assertEq(checkpoints.fromTimestamp, 604801);
        assertEq(checkpoints.owner, address(owner));
        assertEq(checkpoints.delegatedBalance, 0);
        assertEq(checkpoints.delegatee, tokenId3);
        assertEq(escrow.getPastVotes(address(owner), tokenId2, 604802), 0);
        assertEq(escrow.balanceOfNFT(tokenId2), TOKEN_1 * 3);

        // delegatee checkpoint updated
        assertEq(escrow.delegates(tokenId3), 0);
        assertEq(escrow.numCheckpoints(tokenId3), 2);
        checkpoints = escrow.checkpoints(tokenId3, 1);
        assertEq(checkpoints.fromTimestamp, 604802);
        assertEq(checkpoints.owner, address(owner2));
        assertEq(checkpoints.delegatedBalance, TOKEN_1 * 3);
        assertEq(checkpoints.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner2), tokenId3, 604802), TOKEN_1 * 3 + 997260257999312010);
        assertEq(escrow.balanceOfNFT(tokenId3), 997260257999312010);
    }

    function testCannotMergeWithPermanantFrom() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.PermanentLock.selector);
        escrow.merge(tokenId, tokenId2);
    }

    function testMergeWithExpiredFromVeNFT() public {
        // first veNFT max lock time (4yrs)
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 week lock time
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 1 weeks);

        uint256 expectedLockTime = escrow.locked(tokenId).end;

        // let first veNFT expire
        skip(4 weeks);

        uint256 lock = escrow.locked(tokenId2).end;
        assertLt(lock, block.timestamp); // check expired

        vm.expectEmit(true, true, true, true, address(escrow));
        emit Merge(address(owner), tokenId2, tokenId, TOKEN_1, TOKEN_1, TOKEN_1 * 2, expectedLockTime, 3024001);
        vm.expectEmit(false, false, false, true, address(escrow));
        emit MetadataUpdate(tokenId);
        escrow.merge(tokenId2, tokenId);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.ownerOf(tokenId2), address(0));

        IVotingEscrow.UserPoint memory pt2 = escrow.userPointHistory(tokenId2, 2);
        assertEq(uint256(int256(pt2.bias)), 0);
        assertEq(uint256(int256(pt2.slope)), 0);
        assertEq(pt2.ts, 3024001);
        assertEq(pt2.blk, 1);

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId2);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.UserPoint memory pt = escrow.userPointHistory(tokenId, 2);
        uint256 slope = (TOKEN_1 * 2) / MAXTIME;
        uint256 bias = slope * (expectedLockTime - block.timestamp);
        assertEq(uint256(int256(pt.bias)), bias);
        assertEq(uint256(int256(pt.slope)), slope);
        assertEq(pt.ts, 3024001);
        assertEq(pt.blk, 1);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);
    }

    function testCannotMergeWithExpiredToVeNFT() public {
        // first veNFT max lock time (4yrs)
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 week lock time
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 1 weeks);

        // let second veNFT expire
        skip(4 weeks);

        vm.expectRevert(IVotingEscrow.LockExpired.selector);
        escrow.merge(tokenId, tokenId2);
    }

    function testMergeWithVotedToVeNFT() public {
        skip(1 weeks / 2);

        // create a bribe
        LR.approve(address(bribeVotingReward), TOKEN_1);
        bribeVotingReward.notifyRewardAmount(address(LR), TOKEN_1);

        // first veNFT max lock time (4yrs)
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        // second veNFT only 1 yr lock time
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, 365 days);

        uint256 expectedLockTime = escrow.locked(tokenId).end;

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(1, pools, weights);

        skip(1 days);

        // can merge into a veNFT that voted this epoch
        escrow.merge(tokenId2, tokenId);

        assertEq(escrow.balanceOf(address(owner)), 1);
        assertEq(escrow.ownerOf(tokenId), address(owner));
        assertEq(escrow.ownerOf(tokenId2), address(0));

        IVotingEscrow.LockedBalance memory lockedFrom = escrow.locked(tokenId2);
        assertEq(lockedFrom.amount, 0);
        assertEq(lockedFrom.end, 0);

        IVotingEscrow.LockedBalance memory lockedTo = escrow.locked(tokenId);
        assertEq(uint256(uint128(lockedTo.amount)), TOKEN_1 * 2);
        assertEq(uint256(uint128(lockedTo.end)), expectedLockTime);

        skipToNextEpoch(1);

        // to veNFT can still claim rewards
        // rewards
        address[] memory rewards = new address[](1);
        rewards[0] = address(LR);

        uint256 pre = LR.balanceOf(address(owner));
        vm.prank(address(voter));
        bribeVotingReward.getReward(1, rewards);
        uint256 post = LR.balanceOf(address(owner));
        assertEq(post - pre, TOKEN_1);
    }

    function testCannotSplitIfNoOwnerAfterSplit() public {
        escrow.toggleSplit(address(0), true);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.split(tokenId, TOKEN_1 / 2);
        vm.expectRevert(IVotingEscrow.SplitNoOwner.selector);
        escrow.split(tokenId, TOKEN_1 / 4);
    }

    function testCannotSplitIfNoOwnerAfterWithdraw() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(MAXTIME + 1);
        escrow.withdraw(tokenId);
        vm.expectRevert(IVotingEscrow.SplitNoOwner.selector);
        escrow.split(tokenId, TOKEN_1 / 2);
    }

    function testCannotSplitIfNoOwnerAfterMerge() public {
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.merge(tokenId, tokenId2);
        vm.expectRevert(IVotingEscrow.SplitNoOwner.selector);
        escrow.split(tokenId, TOKEN_1 / 4);
    }

    function testCannotSplitOverflow() public {
        escrow.toggleSplit(address(0), true);

        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId2 = escrow.createLock(1e6, MAXTIME);
        // Creates the create overflow amount
        uint256 escrowBalance = AERO.balanceOf(address(escrow));
        uint256 overflowAmount = uint256(int256(int128(-(int256(escrowBalance)))));
        assertGt(overflowAmount, uint256(uint128(type(int128).max)));

        vm.expectRevert(SafeCastLibrary.SafeCastOverflow.selector);
        escrow.split(tokenId2, overflowAmount);
    }

    function testCannotToggleSplitForAllIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IVotingEscrow.NotTeam.selector);
        escrow.toggleSplit(address(0), true);
    }

    function testToggleSplitForAll() public {
        assertFalse(escrow.canSplit(address(0)));

        escrow.toggleSplit(address(0), true);
        assertTrue(escrow.canSplit(address(0)));

        escrow.toggleSplit(address(0), false);
        assertFalse(escrow.canSplit(address(0)));

        escrow.toggleSplit(address(0), true);
        assertTrue(escrow.canSplit(address(0)));
    }

    function testCannotToggleSplitIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IVotingEscrow.NotTeam.selector);
        escrow.toggleSplit(address(owner), true);
    }

    function testToggleSplit() public {
        assertFalse(escrow.canSplit(address(owner)));

        escrow.toggleSplit(address(owner), true);
        assertTrue(escrow.canSplit(address(owner)));

        escrow.toggleSplit(address(owner), false);
        assertFalse(escrow.canSplit(address(owner)));

        escrow.toggleSplit(address(owner), true);
        assertTrue(escrow.canSplit(address(owner)));
    }

    function testCannotSplitWithManagedNFT() public {
        skipAndRoll(1 hours);
        escrow.toggleSplit(address(0), true);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 * 365 * 86400);
        voter.depositManaged(tokenId, mTokenId);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.split(mTokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithZeroAmount() public {
        escrow.toggleSplit(address(0), true);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.ZeroAmount.selector);
        escrow.split(ownerTokenId, 0);
    }

    function testCannotSplitVeNFTWithNoApprovalOrOwnership() public {
        escrow.toggleSplit(address(0), true);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 ownerTokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        vm.prank(address(owner2));
        escrow.split(ownerTokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithExpiredVeNFT() public {
        escrow.toggleSplit(address(0), true);
        // create veNFT with one week locktime
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, 1 weeks);

        // let second veNFT expire
        skip(1 weeks + 1);

        vm.expectRevert(IVotingEscrow.LockExpired.selector);
        escrow.split(tokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithAlreadyVotedVeNFT() public {
        skip(1 hours);
        escrow.toggleSplit(address(0), true);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        skip(1);

        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(tokenId, pools, weights);

        skip(1);

        vm.expectRevert(IVotingEscrow.AlreadyVoted.selector);
        escrow.split(tokenId, TOKEN_1 / 2);
    }

    function testCannotSplitWithAmountTooBig() public {
        escrow.toggleSplit(address(0), true);
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.AmountTooBig.selector);
        escrow.split(tokenId, TOKEN_1);
    }

    function testCannotSplitIfNotPermissioned() public {
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectRevert(IVotingEscrow.SplitNotAllowed.selector);
        escrow.split(1, TOKEN_1 / 4);
    }

    function testSplitWhenToggleSplitOnReceivedNFT() public {
        skip(1 weeks / 2);

        escrow.toggleSplit(address(owner), true);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.transferFrom(address(owner2), address(owner), tokenId);
        vm.stopPrank();

        skipAndRoll(1);
        escrow.split(tokenId, TOKEN_1 / 4);
    }

    function testSplitWhenToggleSplitByApproved() public {
        skip(1 weeks / 2);

        escrow.toggleSplit(address(owner), true);

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.approve(address(owner2), tokenId);
        skipAndRoll(1);

        vm.prank(address(owner2));
        escrow.split(tokenId, TOKEN_1 / 4);
    }

    function testSplitWhenToggleSplitDoesNotTransfer() public {
        skip(1 weeks / 2);

        escrow.toggleSplit(address(owner), true);

        AERO.approve(address(escrow), type(uint256).max);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.transferFrom(address(owner), address(owner2), tokenId);

        skipAndRoll(1);
        vm.expectRevert(IVotingEscrow.SplitNotAllowed.selector);
        vm.prank(address(owner2));
        escrow.split(tokenId, TOKEN_1 / 4);
    }

    function testSplitOwnershipFromOwner() public {
        skip(1 weeks / 2);

        escrow.toggleSplit(address(owner), true);
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit Split(1, 2, 3, address(owner), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));
        assertEq(escrow.ownerOf(1), address(0));
    }

    function testSplitOwnershipFromApproved() public {
        skip(1 weeks / 2);

        escrow.toggleSplit(address(owner), true);
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);
        escrow.approve(address(owner2), 1);

        vm.prank(address(owner2));
        vm.expectEmit(true, true, true, true, address(escrow));
        emit Split(1, 2, 3, address(owner2), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));
        assertEq(escrow.ownerOf(1), address(0));
    }

    function testSplitWithPermanentLock() public {
        skip(1 weeks / 2); // timestamp: 907201
        escrow.toggleSplit(address(0), true);

        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        skipAndRoll(1);

        escrow.split(1, TOKEN_1 / 4); // creates ids 2 and 3

        // check id 1
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);
        assertEq(convert(locked.amount), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(1), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(1, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 907202);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check id 2 (balance: TOKEN_1 * 3 / 4)
        locked = escrow.locked(2);
        assertEq(convert(locked.amount), (TOKEN_1 * 3) / 4);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(2), 1);
        userPoint = escrow.userPointHistory(2, 1);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 907202);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, (TOKEN_1 * 3) / 4);
        assertEq(escrow.balanceOfNFT(2), (TOKEN_1 * 3) / 4);

        locked = escrow.locked(3);
        assertEq(convert(locked.amount), TOKEN_1 / 4);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check id 3 (balance: TOKEN_1 / 4)
        assertEq(escrow.userPointEpoch(3), 1);
        userPoint = escrow.userPointHistory(3, 1);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 907202);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1 / 4);
        assertEq(escrow.balanceOfNFT(3), TOKEN_1 / 4);

        // check global point
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 907202);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        assertEq(escrow.permanentLockBalance(), TOKEN_1);
        assertEq(escrow.totalSupply(), TOKEN_1);
    }

    function testSplitWithDelegatedPermanentFrom() public {
        skip(1 weeks / 2); // timestamp: 907201
        escrow.toggleSplit(address(0), true);

        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        escrow.delegate(1, 2);
        skipAndRoll(1);

        escrow.split(1, TOKEN_1 / 4); // creates ids 3 and 4

        // check id 1
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);
        assertEq(convert(locked.amount), 0);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, false);

        assertEq(escrow.userPointEpoch(1), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(1, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 907202);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, 0);

        // check id 3 (balance: TOKEN_1 * 3 / 4)
        locked = escrow.locked(3);
        assertEq(convert(locked.amount), (TOKEN_1 * 3) / 4);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        assertEq(escrow.userPointEpoch(3), 1);
        userPoint = escrow.userPointHistory(3, 1);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 907202);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, (TOKEN_1 * 3) / 4);
        assertEq(escrow.balanceOfNFT(3), (TOKEN_1 * 3) / 4);

        locked = escrow.locked(4);
        assertEq(convert(locked.amount), TOKEN_1 / 4);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check id 4 (balance: TOKEN_1 / 4)
        assertEq(escrow.userPointEpoch(4), 1);
        userPoint = escrow.userPointHistory(4, 1);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 907202);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1 / 4);
        assertEq(escrow.balanceOfNFT(4), TOKEN_1 / 4);

        // check global point
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 999657518273000010); // tokenId 2 contribution
        assertEq(convert(globalPoint.slope), 7927447995);
        assertEq(globalPoint.ts, 907202);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        // check 1 dedelegates
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 2);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(1, 1);
        assertEq(checkpoint.fromTimestamp, 907202);
        assertEq(checkpoint.owner, address(0));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check 2 delegated balance decrements
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 2);
        checkpoint = escrow.checkpoints(2, 1);
        assertEq(checkpoint.fromTimestamp, 907202);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check 3 voting checkpoint
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 1);
        checkpoint = escrow.checkpoints(3, 0);
        assertEq(checkpoint.fromTimestamp, 907202);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check 4 voting checkpoint
        assertEq(escrow.delegates(4), 0);
        assertEq(escrow.numCheckpoints(4), 1);
        checkpoint = escrow.checkpoints(4, 0);
        assertEq(checkpoint.fromTimestamp, 907202);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
    }

    function testSplitWhenToggleSplit() public {
        skip(1 weeks / 2);

        escrow.toggleSplit(address(owner), true);

        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 1

        // generate new nfts with same amounts / locktime
        escrow.createLock((TOKEN_1 * 3) / 4, MAXTIME); // 2
        escrow.createLock(TOKEN_1 / 4, MAXTIME); // 3
        uint256 expectedLockTime = escrow.locked(1).end;
        uint256 aeroSupply = escrow.supply();

        vm.expectEmit(true, true, true, true, address(escrow));
        emit Split(1, 4, 5, address(owner), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(splitTokenId1, 4);
        assertEq(splitTokenId2, 5);
        assertEq(escrow.supply(), aeroSupply);

        // check new veNFTs have correct amount and locktime
        IVotingEscrow.LockedBalance memory lockedOld = escrow.locked(splitTokenId1);
        assertEq(uint256(uint128(lockedOld.amount)), (TOKEN_1 * 3) / 4);
        assertEq(lockedOld.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));

        IVotingEscrow.LockedBalance memory lockedNew = escrow.locked(splitTokenId2);
        assertEq(uint256(uint128(lockedNew.amount)), TOKEN_1 / 4);
        assertEq(lockedNew.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));

        // check modified veNFTs are equivalent to brand new veNFTs created with same amount and locktime
        assertEq(escrow.balanceOfNFT(splitTokenId1), escrow.balanceOfNFT(2));
        assertEq(escrow.balanceOfNFT(splitTokenId2), escrow.balanceOfNFT(3));

        // Check point history of veNFT that was split from to ensure zero-ed out balance
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);
        assertEq(locked.amount, 0);
        assertEq(locked.end, 0);
        uint256 lastEpochStored = escrow.userPointEpoch(1);
        IVotingEscrow.UserPoint memory point = escrow.userPointHistory(1, lastEpochStored);
        assertEq(point.bias, 0);
        assertEq(point.slope, 0);
        assertEq(point.ts, 907201);
        assertEq(point.blk, 1);
        assertEq(escrow.balanceOfNFT(1), 0);

        // compare point history of first split veNFT and 2
        lastEpochStored = escrow.userPointEpoch(splitTokenId1);
        IVotingEscrow.UserPoint memory origPoint = escrow.userPointHistory(splitTokenId1, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(2);
        IVotingEscrow.UserPoint memory cmpPoint = escrow.userPointHistory(2, lastEpochStored);
        assertEq(origPoint.bias, cmpPoint.bias);
        assertEq(origPoint.slope, cmpPoint.slope);
        assertEq(origPoint.ts, cmpPoint.ts);
        assertEq(origPoint.blk, cmpPoint.blk);

        // compare point history of second split veNFT and 3
        lastEpochStored = escrow.userPointEpoch(splitTokenId2);
        IVotingEscrow.UserPoint memory splitPoint = escrow.userPointHistory(splitTokenId2, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(3);
        cmpPoint = escrow.userPointHistory(3, lastEpochStored);
        assertEq(splitPoint.bias, cmpPoint.bias);
        assertEq(splitPoint.slope, cmpPoint.slope);
        assertEq(splitPoint.ts, cmpPoint.ts);
        assertEq(splitPoint.blk, cmpPoint.blk);
    }

    function testSplitWhenSplitPublic() public {
        skip(1 weeks / 2);

        escrow.toggleSplit(address(0), true);

        AERO.approve(address(escrow), type(uint256).max);
        escrow.createLock(TOKEN_1, MAXTIME); // 1

        // generate new nfts with same amounts / locktime
        escrow.createLock((TOKEN_1 * 3) / 4, MAXTIME); // 2
        escrow.createLock(TOKEN_1 / 4, MAXTIME); // 3
        uint256 expectedLockTime = escrow.locked(1).end;
        uint256 aeroSupply = escrow.supply();

        vm.expectEmit(true, true, true, true, address(escrow));
        emit Split(1, 4, 5, address(owner), (TOKEN_1 * 3) / 4, TOKEN_1 / 4, 127008000, 907201);
        (uint256 splitTokenId1, uint256 splitTokenId2) = escrow.split(1, TOKEN_1 / 4);
        assertEq(splitTokenId1, 4);
        assertEq(splitTokenId2, 5);
        assertEq(escrow.supply(), aeroSupply);

        // check new veNFTs have correct amount and locktime
        IVotingEscrow.LockedBalance memory lockedOld = escrow.locked(splitTokenId1);
        assertEq(uint256(uint128(lockedOld.amount)), (TOKEN_1 * 3) / 4);
        assertEq(lockedOld.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId1), address(owner));

        IVotingEscrow.LockedBalance memory lockedNew = escrow.locked(splitTokenId2);
        assertEq(uint256(uint128(lockedNew.amount)), TOKEN_1 / 4);
        assertEq(lockedNew.end, expectedLockTime);
        assertEq(escrow.ownerOf(splitTokenId2), address(owner));

        // check modified veNFTs are equivalent to brand new veNFTs created with same amount and locktime
        assertEq(escrow.balanceOfNFT(splitTokenId1), escrow.balanceOfNFT(2));
        assertEq(escrow.balanceOfNFT(splitTokenId2), escrow.balanceOfNFT(3));

        // Check point history of veNFT that was split from to ensure zero-ed out balance
        IVotingEscrow.LockedBalance memory locked = escrow.locked(1);
        assertEq(locked.amount, 0);
        assertEq(locked.end, 0);
        uint256 lastEpochStored = escrow.userPointEpoch(1);
        IVotingEscrow.UserPoint memory point = escrow.userPointHistory(1, lastEpochStored);
        assertEq(point.bias, 0);
        assertEq(point.slope, 0);
        assertEq(point.ts, 907201);
        assertEq(point.blk, 1);
        assertEq(escrow.balanceOfNFT(1), 0);

        // compare point history of first split veNFT and 2
        lastEpochStored = escrow.userPointEpoch(splitTokenId1);
        IVotingEscrow.UserPoint memory origPoint = escrow.userPointHistory(splitTokenId1, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(2);
        IVotingEscrow.UserPoint memory cmpPoint = escrow.userPointHistory(2, lastEpochStored);
        assertEq(origPoint.bias, cmpPoint.bias);
        assertEq(origPoint.slope, cmpPoint.slope);
        assertEq(origPoint.ts, cmpPoint.ts);
        assertEq(origPoint.blk, cmpPoint.blk);

        // compare point history of second split veNFT and 3
        lastEpochStored = escrow.userPointEpoch(splitTokenId2);
        IVotingEscrow.UserPoint memory splitPoint = escrow.userPointHistory(splitTokenId2, lastEpochStored);
        lastEpochStored = escrow.userPointEpoch(3);
        cmpPoint = escrow.userPointHistory(3, lastEpochStored);
        assertEq(splitPoint.bias, cmpPoint.bias);
        assertEq(splitPoint.slope, cmpPoint.slope);
        assertEq(splitPoint.ts, cmpPoint.ts);
        assertEq(splitPoint.blk, cmpPoint.blk);
    }

    function testCannotLockPermanentIfNotApprovedOrOwner() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);

        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        vm.prank(address(owner2));
        escrow.lockPermanent(tokenId);
    }

    function testCannotLockPermanentWithManagedNFT() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));

        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.lockPermanent(mTokenId);
    }

    function testCannotLockPermanentWithLockedNFT() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);

        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.lockPermanent(tokenId);
    }

    function testCannotLockPermanentWithExpiredLock() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, 4 weeks);

        skipAndRoll(4 weeks + 1);

        vm.expectRevert(IVotingEscrow.LockExpired.selector);
        escrow.lockPermanent(tokenId);
    }

    function testCannotLockPermamentWithPermanentLock() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);

        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.PermanentLock.selector);
        escrow.lockPermanent(tokenId);
    }

    function testLockPermanent() public {
        // timestamp: 604801
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.locked(tokenId).end, 126403200);
        assertEq(escrow.slopeChanges(0), 0);
        assertEq(escrow.slopeChanges(126403200), -7927447995); // slope is negative after lock creation

        skipAndRoll(1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit LockPermanent(address(owner), tokenId, TOKEN_1, 604802);
        escrow.lockPermanent(tokenId);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 0);
        assertEq(locked.isPermanent, true);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 2);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 2);
        assertEq(convert(userPoint.bias), 0);
        assertEq(convert(userPoint.slope), 0);
        assertEq(userPoint.ts, 604802);
        assertEq(userPoint.blk, 2);
        assertEq(userPoint.permanent, TOKEN_1);

        // check global point updates correctly
        assertEq(escrow.epoch(), 2);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(2);
        assertEq(convert(globalPoint.bias), 0);
        assertEq(convert(globalPoint.slope), 0);
        assertEq(globalPoint.ts, 604802);
        assertEq(globalPoint.blk, 2);
        assertEq(globalPoint.permanentLockBalance, TOKEN_1);

        assertEq(escrow.slopeChanges(0), 0);
        assertEq(escrow.slopeChanges(126403200), 0); // no contribution to global slope
        assertEq(escrow.permanentLockBalance(), TOKEN_1);
    }

    function testCannotUnlockPermanentIfNotApprovedOrOwner() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        vm.prank(address(owner2));
        escrow.unlockPermanent(tokenId);
    }

    function testCannotUnlockPermanentIfNotPermanentlyLocked() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotPermanentLock.selector);
        escrow.unlockPermanent(tokenId);
    }

    function testCannotUnlockPermanentIfManagedNFT() public {
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.unlockPermanent(mTokenId);
    }

    function testCannotUnlockPermanentIfLockedNFT() public {
        skip(1 hours);
        uint256 mTokenId = escrow.createManagedLockFor(address(owner));
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        voter.depositManaged(tokenId, mTokenId);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotNormalNFT.selector);
        escrow.unlockPermanent(mTokenId);
    }

    function testCannotUnlockPermanentIfVoted() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        skipAndRoll(1 hours);

        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10000;
        voter.vote(tokenId, pools, weights);

        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.AlreadyVoted.selector);
        escrow.unlockPermanent(tokenId);
    }

    function testUnlockPermanent() public {
        // timestamp: 604801
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        assertEq(escrow.slopeChanges(126403200), -7927447995); // slope is negative after lock creation
        assertEq(escrow.numCheckpoints(tokenId), 1);

        skipAndRoll(1);

        escrow.lockPermanent(tokenId);
        assertEq(escrow.slopeChanges(126403200), 0); // slope zero on permanent lock

        skipAndRoll(1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit UnlockPermanent(address(owner), tokenId, TOKEN_1, 604803);
        escrow.unlockPermanent(tokenId);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 126403200);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 3);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 3);
        assertEq(convert(userPoint.bias), 997260250071864015); // (TOKEN_1 / MAXTIME) * (126403200 - 604803)
        assertEq(convert(userPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 604803);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 997260250071864015);
        assertEq(convert(globalPoint.slope), 7927447995);
        assertEq(globalPoint.ts, 604803);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.slopeChanges(126403200), -7927447995); // slope restored
        assertEq(escrow.permanentLockBalance(), 0);
        assertEq(escrow.numCheckpoints(tokenId), 1);
    }

    function testUnlockPermanentWithDelegate() public {
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        vm.stopPrank();
        assertEq(escrow.slopeChanges(126403200), -7927447995 * 2); // slope is negative after lock creation

        skipAndRoll(1);

        escrow.lockPermanent(tokenId);
        escrow.delegate(tokenId, tokenId2);
        assertEq(escrow.slopeChanges(126403200), -7927447995);

        skipAndRoll(1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit UnlockPermanent(address(owner), tokenId, TOKEN_1, 604803);
        escrow.unlockPermanent(tokenId);

        // check locked balance state is updated correctly
        IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
        assertEq(convert(locked.amount), TOKEN_1);
        assertEq(locked.end, 126403200);

        // check user point updates correctly
        assertEq(escrow.userPointEpoch(tokenId), 3);
        IVotingEscrow.UserPoint memory userPoint = escrow.userPointHistory(tokenId, 3);
        assertEq(convert(userPoint.bias), 997260250071864015); // (TOKEN_1 / MAXTIME) * (126403200 - 604803)
        assertEq(convert(userPoint.slope), 7927447995); // TOKEN_1 / MAXTIME
        assertEq(userPoint.ts, 604803);
        assertEq(userPoint.blk, 3);
        assertEq(userPoint.permanent, 0);

        // check global point updates correctly
        assertEq(escrow.epoch(), 3);
        IVotingEscrow.GlobalPoint memory globalPoint = escrow.pointHistory(3);
        assertEq(convert(globalPoint.bias), 997260250071864015 * 2); // contribution from tokenId and tokenId2
        assertEq(convert(globalPoint.slope), 7927447995 * 2);
        assertEq(globalPoint.ts, 604803);
        assertEq(globalPoint.blk, 3);
        assertEq(globalPoint.permanentLockBalance, 0);

        assertEq(escrow.slopeChanges(126403200), -7927447995 * 2);
        assertEq(escrow.permanentLockBalance(), 0);

        // check tokenId dedelegates from tokenId2
        assertEq(escrow.delegates(tokenId), 0);
        assertEq(escrow.numCheckpoints(tokenId), 3);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(tokenId, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);

        // check tokenId2 delegated balance is updated
        assertEq(escrow.delegates(tokenId2), 0);
        assertEq(escrow.numCheckpoints(tokenId2), 3);
        checkpoint = escrow.checkpoints(tokenId2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
    }

    function testCannotDelegateIfNotApprovedOrOwner() public {
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        vm.prank(address(owner2));
        escrow.delegate(1, 2);
    }

    function testCannotDelegateIfNotPermanentLock() public {
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NotPermanentLock.selector);
        escrow.delegate(1, 2);
    }

    function testCannotDelegateToNonExistentToken() public {
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        skipAndRoll(1);

        vm.expectRevert(IVotingEscrow.NonExistentToken.selector);
        escrow.delegate(1, 2);
    }

    function testCannotDelegateToBurntToken() public {
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);

        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, (1 weeks)); // 2
        vm.stopPrank();

        skipAndRoll(1 weeks);

        vm.prank(address(owner2));
        escrow.withdraw(2);

        vm.expectRevert(IVotingEscrow.NonExistentToken.selector);
        escrow.delegate(1, 2);
    }

    function testCannotDelegateIfTransferInSameBlock() public {
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        escrow.transferFrom(address(owner), address(owner2), 1);

        vm.expectRevert(IVotingEscrow.OwnershipChange.selector);
        vm.prank(address(owner2));
        escrow.delegate(1, 2);
    }

    function testDelegate() public {
        // timestamp: 604801
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        vm.startPrank(address(owner3));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        // delegate 1 => 2
        vm.expectEmit(true, true, true, false, address(escrow));
        emit DelegateChanged(address(owner), 0, 2);
        escrow.delegate(1, 2);

        // check prior and new checkpoint for tokenId 1
        // expect delegatee 0 => 2
        assertEq(escrow.delegates(1), 2);
        assertEq(escrow.numCheckpoints(1), 2);
        IVotingEscrow.Checkpoint memory checkpoint = escrow.checkpoints(1, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(1, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 2);
        assertEq(escrow.getPastVotes(address(owner), 1, 604802), 0);
        assertEq(escrow.balanceOfNFT(1), TOKEN_1);

        // check prior and new checkpoint for tokenId 2
        // expect delegatedBalance 0 => TOKEN_1
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 2);
        checkpoint = escrow.checkpoints(2, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(2, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604802), TOKEN_1 + 997260257999312010);
        assertEq(escrow.balanceOfNFT(2), 997260257999312010);
        skipAndRoll(1);

        // delegate 1 => 3
        vm.expectEmit(true, true, true, false, address(escrow));
        emit DelegateChanged(address(owner), 2, 3);
        escrow.delegate(1, 3);

        // check prior and new checkpoint for tokenId 1
        // expect delegatee 2 => 3
        assertEq(escrow.delegates(1), 3);
        assertEq(escrow.numCheckpoints(1), 3);
        checkpoint = escrow.checkpoints(1, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 2);
        checkpoint = escrow.checkpoints(1, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 3);
        assertEq(escrow.getPastVotes(address(owner), 1, 604803), 0);
        assertEq(escrow.balanceOfNFT(1), TOKEN_1);

        // check prior and new checkpoint for tokenId 2
        // expect delegatedBalance TOKEN_1 => 0
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 3);
        checkpoint = escrow.checkpoints(2, 1);
        assertEq(checkpoint.fromTimestamp, 604802);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604803), 997260250071864015);
        assertEq(escrow.balanceOfNFT(2), 997260250071864015);

        // check prior and new checkpoint for tokenId 3
        // expect delegatedBalance 0 => TOKEN_1
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 2);
        checkpoint = escrow.checkpoints(3, 0);
        assertEq(checkpoint.fromTimestamp, 604801);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(3, 1);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner3), 3, 604803), TOKEN_1 + 997260250071864015);
        assertEq(escrow.balanceOfNFT(3), 997260250071864015);
        skipAndRoll(1);

        // delegate 1 => 1
        vm.expectEmit(true, true, true, false, address(escrow));
        emit DelegateChanged(address(owner), 3, 0);
        escrow.delegate(1, 1);

        // check prior and new checkpoint for tokenId 1
        // expect delegatee 3 => 0
        assertEq(escrow.delegates(1), 0);
        assertEq(escrow.numCheckpoints(1), 4);
        checkpoint = escrow.checkpoints(1, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 3);
        checkpoint = escrow.checkpoints(1, 3);
        assertEq(checkpoint.fromTimestamp, 604804);
        assertEq(checkpoint.owner, address(owner));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner), 1, 604804), TOKEN_1);
        assertEq(escrow.balanceOfNFT(1), TOKEN_1);

        // check tokenId 2 checkpoint unchanged
        assertEq(escrow.delegates(2), 0);
        assertEq(escrow.numCheckpoints(2), 3);
        checkpoint = escrow.checkpoints(2, 2);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner2));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604804), 997260242144416020);
        assertEq(escrow.balanceOfNFT(2), 997260242144416020);

        // check prior and new checkpoint for tokenId 3
        // expect delegatedBalance TOKEN_1 => 0
        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 3);
        checkpoint = escrow.checkpoints(3, 1);
        assertEq(checkpoint.fromTimestamp, 604803);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, TOKEN_1);
        assertEq(checkpoint.delegatee, 0);
        checkpoint = escrow.checkpoints(3, 2);
        assertEq(checkpoint.fromTimestamp, 604804);
        assertEq(checkpoint.owner, address(owner3));
        assertEq(checkpoint.delegatedBalance, 0);
        assertEq(checkpoint.delegatee, 0);
        assertEq(escrow.getPastVotes(address(owner3), 3, 604804), 997260242144416020);
        assertEq(escrow.balanceOfNFT(3), 997260242144416020);

        skipAndRoll(1);

        // already self delegating, early exit
        escrow.delegate(1, 0);

        assertEq(escrow.delegates(3), 0);
        assertEq(escrow.numCheckpoints(3), 3);

        // yet to delegate
        assertEq(escrow.getPastVotes(address(owner), 1, 604801), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604801), 997260265926760005);
        assertEq(escrow.getPastVotes(address(owner3), 3, 604801), 997260265926760005);
        // 1 => 2
        assertEq(escrow.getPastVotes(address(owner), 1, 604802), 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604802), 997260257999312010 + TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner3), 3, 604802), 997260257999312010);
        // 1 => 3
        assertEq(escrow.getPastVotes(address(owner), 1, 604803), 0);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604803), 997260250071864015);
        assertEq(escrow.getPastVotes(address(owner3), 3, 604803), 997260250071864015 + TOKEN_1);
        // 1 => 1 / 0
        assertEq(escrow.getPastVotes(address(owner), 1, 604804), TOKEN_1);
        assertEq(escrow.getPastVotes(address(owner2), 2, 604804), 997260242144416020);
        assertEq(escrow.getPastVotes(address(owner3), 3, 604804), 997260242144416020);
    }

    function testCannotDelegateBySigWithInvalidNonce() public {
        // timestamp: 604801
        uint256 alicePrivateKey = 0xA11CE;
        address alice = vm.addr(alicePrivateKey);
        deal(address(AERO), alice, TOKEN_100K);

        vm.startPrank(alice);
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        vm.stopPrank();
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        SigUtils.Delegation memory delegation = SigUtils.Delegation({
            delegator: 1,
            delegatee: 2,
            nonce: 1,
            deadline: 608401 // 604801 + 3600
        });
        bytes32 digest = sigUtils.getTypedDataHash(delegation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        vm.expectRevert(IVotingEscrow.InvalidNonce.selector);
        escrow.delegateBySig(1, 2, 1, 608401, v, r, s);
    }

    function testCannotDelegateBySigWithInvalidDeadline() public {
        // timestamp: 604801
        uint256 alicePrivateKey = 0xA11CE;
        address alice = vm.addr(alicePrivateKey);
        deal(address(AERO), alice, TOKEN_100K);

        vm.startPrank(alice);
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        vm.stopPrank();
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        SigUtils.Delegation memory delegation = SigUtils.Delegation({
            delegator: 1,
            delegatee: 2,
            nonce: 0,
            deadline: 604801
        });
        bytes32 digest = sigUtils.getTypedDataHash(delegation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        vm.expectRevert(IVotingEscrow.SignatureExpired.selector);
        escrow.delegateBySig(1, 2, 0, 604801, v, r, s);
    }

    function testCannotDelegateBySigIfNotOwnerOrApproved() public {
        // timestamp: 604801
        uint256 alicePrivateKey = 0xA11CE;
        address alice = vm.addr(alicePrivateKey);
        deal(address(AERO), alice, TOKEN_100K);

        vm.startPrank(alice);
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        vm.stopPrank();
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        SigUtils.Delegation memory delegation = SigUtils.Delegation({
            delegator: 1,
            delegatee: 2,
            nonce: 0,
            deadline: 608401 // 604801 + 3600
        });
        bytes32 digest = sigUtils.getTypedDataHash(delegation);
        uint256 bobPrivateKey = 0xB0B;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);

        vm.expectRevert(IVotingEscrow.NotApprovedOrOwner.selector);
        escrow.delegateBySig(1, 2, 0, 608401, v, r, s);
    }

    function testDelegateBySig() public {
        // timestamp: 604801
        uint256 alicePrivateKey = 0xA11CE;
        address alice = vm.addr(alicePrivateKey);
        deal(address(AERO), alice, TOKEN_100K);

        vm.startPrank(alice);
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 1
        escrow.lockPermanent(1);
        vm.stopPrank();
        vm.startPrank(address(owner2));
        AERO.approve(address(escrow), TOKEN_1);
        escrow.createLock(TOKEN_1, MAXTIME); // 2
        vm.stopPrank();
        skipAndRoll(1);

        SigUtils.Delegation memory delegation = SigUtils.Delegation({
            delegator: 1,
            delegatee: 2,
            nonce: 0,
            deadline: 608401 // 604801 + 3600
        });
        bytes32 digest = sigUtils.getTypedDataHash(delegation);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        escrow.delegateBySig(1, 2, 0, 608401, v, r, s);

        assertEq(escrow.delegates(1), 2);
    }

    /// invariant checks
    /// bound timestamp between 1600000000 and 100 years from then
    /// current base timestamp >= 1600000000
    function testBalanceOfNFTWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.warp(timestamp);

        assertEq(escrow.balanceOfNFT(tokenId), TOKEN_1);
    }

    function testBalanceOfNFTAtWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.warp(timestamp);

        assertEq(escrow.balanceOfNFTAt(tokenId, timestamp), TOKEN_1);
    }

    function testTotalSupplyWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000001, 1600000000 + (52 weeks) * 100);

        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.warp(timestamp);

        assertEq(escrow.totalSupply(), TOKEN_1);
        assertEq(escrow.getPastTotalSupply(timestamp), TOKEN_1);
        assertEq(escrow.getPastTotalSupply(timestamp - 1), TOKEN_1);
        assertEq(escrow.getPastTotalSupply(1600000000), TOKEN_1);
    }

    function testTotalSupplyAtWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000001, 1600000000 + (52 weeks) * 100);

        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.warp(timestamp);

        assertEq(escrow.getPastTotalSupply(timestamp), TOKEN_1);
        assertEq(escrow.getPastTotalSupply(timestamp - 1), TOKEN_1);
        assertEq(escrow.getPastTotalSupply(1600000000), TOKEN_1);
    }

    function testBalanceAndSupplyInvariantsWithPermanentLocks(uint256 timestamp) public {
        vm.warp(1600000000);
        timestamp = bound(timestamp, 1600000000, 1600000000 + (52 weeks) * 100);

        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId = escrow.createLock(TOKEN_1, MAXTIME);
        AERO.approve(address(escrow), TOKEN_1);
        uint256 tokenId2 = escrow.createLock(TOKEN_1, MAXTIME);
        escrow.lockPermanent(tokenId);
        vm.warp(timestamp);

        assertEq(escrow.balanceOfNFT(tokenId) + escrow.balanceOfNFT(tokenId2), escrow.totalSupply());
        assertEq(
            escrow.balanceOfNFTAt(tokenId, timestamp) + escrow.balanceOfNFTAt(tokenId2, timestamp),
            escrow.getPastTotalSupply(timestamp)
        );
    }

    function testCannotSetArtProxyIfNotTeam() public {
        VeArtProxy artProxy2 = new VeArtProxy(address(escrow));

        vm.expectRevert();
        vm.prank(address(owner2));
        escrow.setArtProxy(address(artProxy2));
    }

    function testSetArtProxy() public {
        assertEq(escrow.artProxy(), address(artProxy));
        VeArtProxy artProxy2 = new VeArtProxy(address(escrow));

        vm.expectEmit(false, false, false, true, address(escrow));
        emit BatchMetadataUpdate(0, type(uint256).max);
        escrow.setArtProxy(address(artProxy2));

        assertEq(escrow.artProxy(), address(artProxy2));
    }
}
