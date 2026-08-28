// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IGaugeFactory} from "../interfaces/factories/IGaugeFactory.sol";
import {Gauge} from "../gauges/Gauge.sol";

contract GaugeFactory is IGaugeFactory {
    function createGauge(
        address _forwarder,
        address _pool,
        address _feesVotingReward,
        address _rewardToken,
        bool isPool
    ) external returns (address gauge) {
        gauge = address(new Gauge(_forwarder, _pool, _feesVotingReward, _rewardToken, msg.sender, isPool));
    }
}
