// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../script/DeployCore.s.sol";
import "../script/DeployGaugesAndPools.s.sol";
import {SafeCastLibrary} from "../contracts/libraries/SafeCastLibrary.sol";

import "./BaseTest.sol";

contract MinterAirdrop is BaseTest {
    using SafeCastLibrary for int128;

    event DistributeLocked(address indexed _destination, uint256 _amount, uint256 _tokenId);
    event DistributeLiquid(address indexed _destination, uint256 _amount);

    uint256 public constant WALLET_NUMBER = 5;

    constructor() {
        deploymentType = Deployment.DEFAULT;
    }

    function testInitializeFullAirdrop() public {
        (address[] memory liquidWallets, uint256[] memory liquidAmounts) = _getWalletsAmounts(WALLET_NUMBER, TOKEN_1M);
        (address[] memory lockedWallets, uint256[] memory lockedAmounts) = _getWalletsAmounts(
            WALLET_NUMBER,
            TOKEN_100K
        );
        uint256 preAeroBal = AERO.balanceOf(address(this));

        // Expects all events from the airdrop
        uint256 liquidLen = liquidWallets.length;
        for (uint256 i = 0; i < liquidLen; i++) {
            vm.expectEmit(true, false, false, true);
            emit DistributeLiquid(liquidWallets[i], liquidAmounts[i]);
        }
        uint256 lockedLen = lockedWallets.length;
        for (uint256 i = 0; i < lockedLen; i++) {
            vm.expectEmit(true, false, false, true);
            emit DistributeLocked(lockedWallets[i], lockedAmounts[i], i + 1);
        }

        // Airdrops All Tokens
        vm.prank(minter.team());
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: liquidWallets,
                liquidAmounts: liquidAmounts,
                lockedWallets: lockedWallets,
                lockedAmounts: lockedAmounts
            })
        );
        assertTrue(minter.initialized());
        // Ensures Liquid Tokens were minted correctly
        for (uint256 i = 0; i < liquidLen; i++) {
            assertEq(AERO.balanceOf(liquidWallets[i]), liquidAmounts[i]);
        }
        // Ensures permanently locked NFTs were distributed correctly
        for (uint256 i = 0; i < lockedLen; i++) {
            uint256 tokenId = i + 1;
            assertEq(escrow.balanceOf(lockedWallets[i]), 1);
            IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
            assertEq(locked.amount.toUint256(), lockedAmounts[i]);
            assertTrue(locked.isPermanent);
            assertEq(locked.end, 0);
        }
        // Minter balance remains unchanged
        assertEq(AERO.balanceOf(address(this)), preAeroBal);
        assertEq(escrow.balanceOf(address(this)), 0);
    }

    function testInitializeAeroAirdrop() public {
        (address[] memory wallets, uint256[] memory amounts) = _getWalletsAmounts(WALLET_NUMBER, TOKEN_1M);
        uint256 preAeroBal = AERO.balanceOf(address(this));

        uint256 len = wallets.length;
        // Expects all events to be emitted
        for (uint256 i = 0; i < len; i++) {
            vm.expectEmit(true, false, false, true);
            emit DistributeLiquid(wallets[i], amounts[i]);
        }

        // Airdrop Liquid Tokens
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: wallets,
                liquidAmounts: amounts,
                lockedWallets: new address[](0),
                lockedAmounts: new uint256[](0)
            })
        );

        assertTrue(minter.initialized());
        // Ensures tokens were minted correctly
        for (uint256 i = 0; i < len; i++) {
            assertEq(AERO.balanceOf(wallets[i]), amounts[i]);
        }
        // Minter balance remains unchanged
        assertEq(AERO.balanceOf(address(this)), preAeroBal);
        assertEq(escrow.balanceOf(address(this)), 0);
    }

    function testInitializeVeAirdrop() public {
        (address[] memory wallets, uint256[] memory amounts) = _getWalletsAmounts(WALLET_NUMBER, TOKEN_100K);
        uint256 preAeroBal = AERO.balanceOf(address(this));

        uint256 len = wallets.length;
        // Expects all events to be emitted
        for (uint256 i = 0; i < len; i++) {
            vm.expectEmit(true, false, false, true);
            emit DistributeLocked(wallets[i], amounts[i], i + 1);
        }

        // Airdrop Locked NFTs
        vm.prank(minter.team());
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: new address[](0),
                liquidAmounts: new uint256[](0),
                lockedWallets: wallets,
                lockedAmounts: amounts
            })
        );

        assertTrue(minter.initialized());
        // Ensures tokens and locks were distributed correctly
        for (uint256 i = 0; i < len; i++) {
            uint256 tokenId = i + 1;
            assertEq(escrow.balanceOf(wallets[i]), 1);
            IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
            assertEq(locked.amount.toUint256(), amounts[i]);
            assertTrue(locked.isPermanent);
            assertEq(locked.end, 0);
        }
        // Minter balance remains unchanged
        assertEq(AERO.balanceOf(address(this)), preAeroBal);
        assertEq(escrow.balanceOf(address(this)), 0);
    }

    function testCannotInitializeInvalidParams() public {
        // Creating arrays with different lengths to lead to revert
        (address[] memory liquidWallets, uint256[] memory liquidAmounts) = _getWalletsAmounts(WALLET_NUMBER, TOKEN_1M);
        (address[] memory lockedWallets, uint256[] memory lockedAmounts) = _getWalletsAmounts(
            WALLET_NUMBER - 1,
            TOKEN_100K
        );

        vm.startPrank(minter.team());
        vm.expectRevert(IMinter.InvalidParams.selector);
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: liquidWallets,
                liquidAmounts: lockedAmounts,
                lockedWallets: new address[](0),
                lockedAmounts: new uint256[](0)
            })
        );

        vm.expectRevert(IMinter.InvalidParams.selector);
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: new address[](0),
                liquidAmounts: new uint256[](0),
                lockedWallets: lockedWallets,
                lockedAmounts: liquidAmounts
            })
        );

        vm.expectRevert(IMinter.InvalidParams.selector);
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: liquidWallets,
                liquidAmounts: lockedAmounts,
                lockedWallets: lockedWallets,
                lockedAmounts: liquidAmounts
            })
        );
        vm.stopPrank();
        assertFalse(minter.initialized());
    }

    function testCannotInitializeAlreadyInitialized() public {
        vm.startPrank(address(owner));
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: new address[](0),
                liquidAmounts: new uint256[](0),
                lockedWallets: new address[](0),
                lockedAmounts: new uint256[](0)
            })
        );
        assertTrue(minter.initialized());

        vm.expectRevert(IMinter.AlreadyInitialized.selector);
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: new address[](0),
                liquidAmounts: new uint256[](0),
                lockedWallets: new address[](0),
                lockedAmounts: new uint256[](0)
            })
        );
        vm.stopPrank();
    }

    function testCannotInitializeIfNotTeam() public {
        vm.prank(address(owner2));
        vm.expectRevert(IMinter.NotTeam.selector);
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: new address[](0),
                liquidAmounts: new uint256[](0),
                lockedWallets: new address[](0),
                lockedAmounts: new uint256[](0)
            })
        );
    }

    function _getWalletsAmounts(
        uint256 walletQuantity,
        uint256 amount
    ) internal pure returns (address[] memory _wallets, uint256[] memory _amounts) {
        _wallets = new address[](walletQuantity);
        _amounts = new uint256[](walletQuantity);

        for (uint32 i = 0; i < walletQuantity; i++) {
            _wallets[i] = vm.addr(i + 1);
            // Multiplying by i+1 to test different amounts
            _amounts[i] = (i + 1) * amount;
        }
    }
}
