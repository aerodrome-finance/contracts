// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract VeArtProxyTest is BaseTest {
    uint256 tokenId;

    /**
    Assumptions
     * 1 <= seed <= 1000
     * 4 <= lineCount <= 32 (8 digits or 10M aero) - must be multiple of 4
     * viewbox is (0, 0) to (4000, 4000)
     */

    function _setUp() public override {
        // create tokenId
        skipAndRoll(1 hours);
        AERO.approve(address(escrow), TOKEN_1);
        tokenId = escrow.createLock(TOKEN_1, MAXTIME);
    }

    function _setupFuzz(
        uint256 lineCount,
        uint256 seed1,
        uint256 seed2,
        uint256 seed3
    ) internal view returns (VeArtProxy.Config memory cfg) {
        lineCount = bound(lineCount, 4, 32);
        vm.assume(lineCount % 4 == 0);

        seed1 = bound(seed1, 1, 999);
        seed2 = bound(seed2, 1, 999);
        seed3 = bound(seed3, 1, 999);

        cfg.maxLines = int256(lineCount);
        cfg.seed1 = int256(seed1);
        cfg.seed2 = int256(seed2);
        cfg.seed3 = int256(seed3);
    }

    function testFuzz_drawTwoStripes(uint256 lineCount, uint256 seed1, uint256 seed2, uint256 seed3) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, seed2, seed3);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.twoStripes(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }

    function testFuzz_drawCircles(uint256 lineCount, uint256 seed1, uint256 seed2, uint256 seed3) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, seed2, seed3);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.circles(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }

    function testFuzz_drawInterlockingCircles(uint256 lineCount, uint256 seed1, uint256 seed2) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, seed2, 1);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.interlockingCircles(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }

    function testFuzz_drawCorners(uint256 lineCount, uint256 seed1) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, 1, 1);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.corners(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }

    function testFuzz_drawCurves(uint256 lineCount, uint256 seed1) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, 1, 1);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.curves(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }

    function testFuzz_drawSpiral(uint256 lineCount, uint256 seed1, uint256 seed2) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, seed2, 1);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.spiral(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }

    function testFuzz_drawExplosion(uint256 lineCount, uint256 seed1, uint256 seed2, uint256 seed3) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, seed2, seed3);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.explosion(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }

    function testFuzz_drawWormhole(uint256 lineCount, uint256 seed1, uint256 seed2) external {
        bool lineAppears;
        VeArtProxy.Config memory cfg = _setupFuzz(lineCount, seed1, seed2, 1);

        for (int256 l = 0; l < cfg.maxLines; l++) {
            VeArtProxy.Point[100] memory Line = artProxy.wormhole(cfg, l);

            for (uint256 i = 0; i < 100; i++) {
                VeArtProxy.Point memory pt = Line[i];
                if (pt.x < 4001 && pt.y < 4001) {
                    lineAppears = true;
                    break;
                }
            }
            if (lineAppears) break;
        }
        assertTrue(lineAppears);
    }
}
