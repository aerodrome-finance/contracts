// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Gauge} from "contracts/gauges/Gauge.sol";

contract TestOwner {
    /*//////////////////////////////////////////////////////////////
                               IERC20
    //////////////////////////////////////////////////////////////*/

    function approve(address _token, address _spender, uint256 _amount) public {
        IERC20(_token).approve(_spender, _amount);
    }

    function transfer(address _token, address _to, uint256 _amount) public {
        IERC20(_token).transfer(_to, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 Gauge
    //////////////////////////////////////////////////////////////*/

    function getGaugeReward(address _gauge, address _account) public {
        Gauge(_gauge).getReward(_account);
    }

    function deposit(address _gauge, uint256 _amount) public {
        Gauge(_gauge).deposit(_amount);
    }

    function withdrawGauge(address _gauge, uint256 _amount) public {
        Gauge(_gauge).withdraw(_amount);
    }

    receive() external payable {}
}
