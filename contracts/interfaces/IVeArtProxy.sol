// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IVeArtProxy {
    /// @dev Art configuration
    struct Config {
        // NFT metadata variables
        int256 _tokenId;
        int256 _balanceOf;
        int256 _lockedEnd;
        int256 _lockedAmount;
        // Line art variables
        int256 shape;
        uint256 palette;
        int256 maxLines;
        int256 dash;
        // Randomness variables
        int256 seed1;
        int256 seed2;
        int256 seed3;
    }

    /// @dev Individual line art path variables.
    struct lineConfig {
        string color;
        uint256 stroke;
        uint256 offset;
        uint256 offsetHalf;
        uint256 offsetDashSum;
        uint256 pathLength;
    }

    /// @dev Represents an (x,y) coordinate in a line.
    struct Point {
        int256 x;
        int256 y;
    }

    /// @notice Generate a SVG based on veNFT metadata
    /// @param _tokenId Unique veNFT identifier
    /// @return output SVG metadata as HTML tag
    function tokenURI(uint256 _tokenId) external view returns (string memory output);

    /// @notice Generate only the foreground <path> elements of the line art for an NFT (excluding SVG header), for flexibility purposes.
    /// @param _tokenId Unique veNFT identifier
    /// @return output Encoded output of generateShape()
    function lineArtPathsOnly(uint256 _tokenId) external view returns (bytes memory output);

    /// @notice Generate the master art config metadata for a veNFT
    /// @param _tokenId Unique veNFT identifier
    /// @return cfg Config struct
    function generateConfig(uint256 _tokenId) external view returns (Config memory cfg);

    /// @notice Generate the points for two stripe lines based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of line drawn
    /// @return Line (x, y) coordinates of the drawn stripes
    function twoStripes(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);

    /// @notice Generate the points for circles based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of circles drawn
    /// @return Line (x, y) coordinates of the drawn circles
    function circles(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);

    /// @notice Generate the points for interlocking circles based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of interlocking circles drawn
    /// @return Line (x, y) coordinates of the drawn interlocking circles
    function interlockingCircles(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);

    /// @notice Generate the points for corners based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of corners drawn
    /// @return Line (x, y) coordinates of the drawn corners
    function corners(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);

    /// @notice Generate the points for a curve based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of curve drawn
    /// @return Line (x, y) coordinates of the drawn curve
    function curves(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);

    /// @notice Generate the points for a spiral based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of spiral drawn
    /// @return Line (x, y) coordinates of the drawn spiral
    function spiral(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);

    /// @notice Generate the points for an explosion based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of explosion drawn
    /// @return Line (x, y) coordinates of the drawn explosion
    function explosion(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);

    /// @notice Generate the points for a wormhole based on the config generated for a veNFT
    /// @param cfg Master art config metadata of a veNFT
    /// @param l Number of wormhole drawn
    /// @return Line (x, y) coordinates of the drawn wormhole
    function wormhole(Config memory cfg, int256 l) external pure returns (Point[100] memory Line);
}
