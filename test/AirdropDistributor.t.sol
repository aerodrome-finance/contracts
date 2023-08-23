// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import {SafeCastLibrary} from "../contracts/libraries/SafeCastLibrary.sol";

import "./BaseTest.sol";

contract AirdropDistributorTest is BaseTest {
    using stdStorage for StdStorage;
    using SafeCastLibrary for int128;

    event Airdrop(address indexed _destination, uint256 _amount, uint256 _tokenId);

    uint256 public constant N_TEST_WALLETS = 66;
    uint256 public constant INITIAL_DISTRIBUTOR_BALANCE = TOKEN_100M;

    constructor() {
        deploymentType = Deployment.DEFAULT;
    }

    function _setUp() public override {
        address[] memory _wallets = new address[](1);
        uint256[] memory _amounts = new uint256[](1);
        _wallets[0] = address(airdrop);
        _amounts[0] = INITIAL_DISTRIBUTOR_BALANCE;

        // Mints tokens to Airdrop Distributor
        assertEq(AERO.balanceOf(address(airdrop)), 0);
        vm.prank(minter.team());
        minter.initialize(
            IMinter.AirdropParams({
                liquidWallets: _wallets,
                liquidAmounts: _amounts,
                lockedWallets: new address[](0),
                lockedAmounts: new uint256[](0)
            })
        );
    }

    function testAirdropDistributorDeployment() public {
        assertEq(airdrop.owner(), address(owner));
        assertEq(address(airdrop.ve()), address(escrow));
        assertEq(address(airdrop.aero()), address(AERO));
        assertEq(AERO.balanceOf(address(airdrop)), INITIAL_DISTRIBUTOR_BALANCE);
        assertEq(escrow.balanceOf(address(airdrop)), 0);
    }

    function testAirdropDistributor() public {
        uint256 preAeroBal = AERO.balanceOf(address(airdrop));

        (address[] memory _wallets, uint256[] memory _amounts) = _getWalletsAmounts(N_TEST_WALLETS, TOKEN_10K);
        uint256 _len = _wallets.length;
        uint256 sum;
        // Ensures AirdropDistributor has enough balance
        for (uint256 i = 0; i < _len; i++) {
            sum += _amounts[i];
        }
        assertGe(AERO.balanceOf(address(airdrop)), sum);

        // Expects emission of all events from the Airdrop
        for (uint256 i = 0; i < _len; i++) {
            vm.expectEmit(true, false, false, true, address(airdrop));
            emit Airdrop(_wallets[i], _amounts[i], i + 1);
        }
        // Airdrops tokens
        vm.prank(address(owner));
        airdrop.distributeTokens(_wallets, _amounts);
        uint256 newAeroBal = AERO.balanceOf(address(airdrop));

        // Asserts Distributor's token balances
        assertEq(preAeroBal - sum, newAeroBal);
        assertEq(escrow.balanceOf(address(airdrop)), 0);
        // Ensures every token is permanently locked, with the rightful amount and predicted TokenId
        for (uint256 i = 0; i < _len; i++) {
            uint256 tokenId = i + 1;
            assertEq(escrow.balanceOf(_wallets[i]), 1);
            IVotingEscrow.LockedBalance memory locked = escrow.locked(tokenId);
            assertEq(locked.amount.toUint256(), _amounts[i]);
            assertTrue(locked.isPermanent);
            assertEq(locked.end, 0);
        }
    }

    function testCannotAirdropIfInvalidParams() public {
        (address[] memory _wallets, ) = _getWalletsAmounts(N_TEST_WALLETS, TOKEN_10K);
        (, uint256[] memory _amounts) = _getWalletsAmounts(N_TEST_WALLETS + 1, TOKEN_10K);

        vm.prank(address(owner));
        vm.expectRevert(IAirdropDistributor.InvalidParams.selector);
        airdrop.distributeTokens(_wallets, _amounts);
    }

    function testCannotAirdropIfNotOwner() public {
        (address[] memory _wallets, uint256[] memory _amounts) = _getWalletsAmounts(N_TEST_WALLETS, TOKEN_10K);

        vm.prank(address(owner2));
        vm.expectRevert("Ownable: caller is not the owner");
        airdrop.distributeTokens(_wallets, _amounts);
    }

    function testCannotAirdropIfInsufficientBalance() public {
        address[] memory _wallets = new address[](1);
        uint256[] memory _amounts = new uint256[](1);
        _wallets[0] = address(owner2);
        _amounts[0] = INITIAL_DISTRIBUTOR_BALANCE;
        uint256 _len = _wallets.length;
        uint256 sum;
        // Ensures AirdropDistributor has enough balance
        for (uint256 i = 0; i < _len; i++) {
            sum += _amounts[i];
        }
        stdstore.target(address(AERO)).sig("balanceOf(address)").with_key(address(airdrop)).checked_write(sum - 1);

        vm.expectRevert(IAirdropDistributor.InsufficientBalance.selector);
        airdrop.distributeTokens(_wallets, _amounts);
        assertEq(AERO.balanceOf(address(airdrop)), sum - 1);
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
