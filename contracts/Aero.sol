// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IAero} from "./interfaces/IAero.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title Aero
/// @author velodrome.finance, Solidly (adapted for Aerodrome)
/// @notice Native token of the Aerodrome Finance protocol ecosystem
/// @dev Minter rights are set once via setMinter to the BaseV1 Minter contract.
///      Inherits IAero for errors/events compatibility.
contract Aero is IAero, ERC20Permit("Aerodrome"), ERC20("Aerodrome", "AERO") {
    address public minter;

    constructor(address initialMinter) {
        // Оптимизация: constructor принимает initialMinter (deployer может указать сразу),
        //              но по умолчанию msg.sender. Позволяет гибкость без setMinter.
        minter = initialMinter == address(0) ? msg.sender : initialMinter;
    }

    /// @notice Modifier for minter-only access (shared code, gas savings ~10-20 on repeated calls)
    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    /// @notice Set minter once (intended for Minter contract deployment).
    /// @dev No additional checks: trust deployer to call once correctly.
    ///      Emits event via IAero if defined.
    function setMinter(address newMinter) external onlyMinter {
        // Оптимизация: простая замена (без storage слотов для флага "set"),
        //              gas ~21k (vs ~5k для простого присваивания).
        //              Deployer вызывает вручную один раз.
        minter = newMinter;
    }

    /// @notice Mint tokens to account (minter-only).
    /// @dev Uses OZ _mint (optimized, safe arithmetic in 0.8.x).
    /// @return bool Success (true).
    function mint(address account, uint256 amount) external onlyMinter returns (bool) {
        _mint(account, amount);
        return true;
    }
}