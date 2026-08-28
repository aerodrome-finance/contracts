// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev MockERC20 contract where there is a fee in transfer for testing use only
contract MockERC20WithTransferFee is ERC20 {
    uint8 private _decimals;
    uint256 public fee = 69;

    constructor(string memory name_, string memory symbol_, uint256 decimals_) ERC20(name_, symbol_) {
        _decimals = uint8(decimals_);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        // only do fees if not in a _mint or _burn
        if (from == address(0) || to == address(0)) return;

        if (amount > fee) {
            _burn(to, fee);
        }
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
