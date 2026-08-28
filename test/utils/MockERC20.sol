// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev MockERC20 contract for testing use only
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint256 decimals_) ERC20(name_, symbol_) {
        _decimals = uint8(decimals_);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
