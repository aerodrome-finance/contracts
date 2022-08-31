// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVelo} from "./IVelo.sol";

interface ISinkManager {
    event ConvertVELO(address who, uint256 amount, uint256 timestamp);
    event ConvertVe(
        address who,
        uint256 amount,
        uint256 lockEnd,
        uint256 tokenId,
        uint256 tokenIdV2,
        uint256 timestamp
    );
    event ClaimRebaseAndGaugeRewards(
        address who,
        uint256 amountResidual,
        uint256 amountRewarded,
        uint256 amountRebased,
        uint256 timestamp
    );

    function ownedTokenId() external view returns (uint256);

    function velo() external view returns (IVelo);

    function veloV2() external view returns (IVelo);

    /// @notice Helper utility that returns amount of token captured by epoch
    function captured(uint256 timestamp) external view returns (uint256 amount);

    /// @notice User converts their v1 VELO into v2 VELO
    /// @param amount Amount of VELO to convert
    function convertVELO(uint256 amount) external;

    /// @notice User converts their v1 ve into v2 ve
    /// @param tokenId      Token ID of v1 ve
    /// @return tokenIdV2   Token ID of v2 ve
    function convertVe(uint256 tokenId) external returns (uint256 tokenIdV2);

    /// @notice Claim SinkManager-eligible rebase and gauge rewards to lock into the SinkManager-owned tokenId
    /// @dev Callable by anyone
    function claimRebaseAndGaugeRewards() external;
}
