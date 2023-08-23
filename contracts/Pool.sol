// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IPoolCallee} from "./interfaces/IPoolCallee.sol";
import {IPoolFactory} from "./interfaces/factories/IPoolFactory.sol";
import {PoolFees} from "./PoolFees.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Pool
/// @author velodrome.finance, @figs999, @pegahcarter
/// @notice Protocol token pool, either stable or volatile
contract Pool is IPool, ERC20Permit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;
    address private _voter;

    /// @inheritdoc IPool
    bool public stable;

    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 internal constant MINIMUM_K = 10 ** 10;

    /// @inheritdoc IPool
    address public token0;
    /// @inheritdoc IPool
    address public token1;
    /// @inheritdoc IPool
    address public poolFees;
    /// @inheritdoc IPool
    address public factory;

    /// @inheritdoc IPool
    uint256 public constant periodSize = 1800;

    Observation[] public observations;

    uint256 internal decimals0;
    uint256 internal decimals1;

    /// @inheritdoc IPool
    uint256 public reserve0;
    /// @inheritdoc IPool
    uint256 public reserve1;
    /// @inheritdoc IPool
    uint256 public blockTimestampLast;

    /// @inheritdoc IPool
    uint256 public reserve0CumulativeLast;
    /// @inheritdoc IPool
    uint256 public reserve1CumulativeLast;

    /// @inheritdoc IPool
    uint256 public index0 = 0;
    /// @inheritdoc IPool
    uint256 public index1 = 0;

    /// @inheritdoc IPool
    mapping(address => uint256) public supplyIndex0;
    /// @inheritdoc IPool
    mapping(address => uint256) public supplyIndex1;

    /// @inheritdoc IPool
    mapping(address => uint256) public claimable0;
    /// @inheritdoc IPool
    mapping(address => uint256) public claimable1;

    constructor() ERC20("", "") ERC20Permit("") {}

    /// @inheritdoc IPool
    function initialize(address _token0, address _token1, bool _stable) external {
        if (factory != address(0)) revert FactoryAlreadySet();
        factory = _msgSender();
        _voter = IPoolFactory(factory).voter();
        (token0, token1, stable) = (_token0, _token1, _stable);
        poolFees = address(new PoolFees(_token0, _token1));
        string memory symbol0 = ERC20(_token0).symbol();
        string memory symbol1 = ERC20(_token1).symbol();
        if (_stable) {
            _name = string(abi.encodePacked("Stable AMM - ", symbol0, "/", symbol1));
            _symbol = string(abi.encodePacked("sAMM-", symbol0, "/", symbol1));
        } else {
            _name = string(abi.encodePacked("Volatile AMM - ", symbol0, "/", symbol1));
            _symbol = string(abi.encodePacked("vAMM-", symbol0, "/", symbol1));
        }

        decimals0 = 10 ** ERC20(_token0).decimals();
        decimals1 = 10 ** ERC20(_token1).decimals();

        observations.push(Observation(block.timestamp, 0, 0));
    }

    /// @inheritdoc IPool
    function setName(string calldata __name) external {
        if (msg.sender != IVoter(_voter).emergencyCouncil()) revert NotEmergencyCouncil();
        _name = __name;
    }

    /// @inheritdoc IPool
    function setSymbol(string calldata __symbol) external {
        if (msg.sender != IVoter(_voter).emergencyCouncil()) revert NotEmergencyCouncil();
        _symbol = __symbol;
    }

    /// @inheritdoc IPool
    function observationLength() external view returns (uint256) {
        return observations.length;
    }

    /// @inheritdoc IPool
    function lastObservation() public view returns (Observation memory) {
        return observations[observations.length - 1];
    }

    /// @inheritdoc IPool
    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1)
    {
        return (decimals0, decimals1, reserve0, reserve1, stable, token0, token1);
    }

    /// @inheritdoc IPool
    function tokens() external view returns (address, address) {
        return (token0, token1);
    }

    /// @inheritdoc IPool
    function getK() external nonReentrant returns (uint256) {
        return _k(reserve0, reserve1);
    }

    /// @inheritdoc IPool
    function claimFees() external returns (uint256 claimed0, uint256 claimed1) {
        address sender = _msgSender();
        _updateFor(sender);

        claimed0 = claimable0[sender];
        claimed1 = claimable1[sender];

        if (claimed0 > 0 || claimed1 > 0) {
            claimable0[sender] = 0;
            claimable1[sender] = 0;

            PoolFees(poolFees).claimFeesFor(sender, claimed0, claimed1);

            emit Claim(sender, sender, claimed0, claimed1);
        }
    }

    /// @dev Accrue fees on token0
    function _update0(uint256 amount) internal {
        // Only update on this pool if there is a fee
        if (amount == 0) return;
        IERC20(token0).safeTransfer(poolFees, amount); // transfer the fees out to PoolFees
        uint256 _ratio = (amount * 1e18) / totalSupply(); // 1e18 adjustment is removed during claim
        if (_ratio > 0) {
            index0 += _ratio;
        }
        emit Fees(_msgSender(), amount, 0);
    }

    /// @dev Accrue fees on token1
    function _update1(uint256 amount) internal {
        // Only update on this pool if there is a fee
        if (amount == 0) return;
        IERC20(token1).safeTransfer(poolFees, amount);
        uint256 _ratio = (amount * 1e18) / totalSupply();
        if (_ratio > 0) {
            index1 += _ratio;
        }
        emit Fees(_msgSender(), 0, amount);
    }

    /// @dev This function MUST be called on any balance changes, otherwise can be used to infinitely claim fees
    ///      Fees are segregated from core funds, so fees can never put liquidity at risk.
    function _updateFor(address recipient) internal {
        uint256 _supplied = balanceOf(recipient); // get LP balance of `recipient`
        if (_supplied > 0) {
            uint256 _supplyIndex0 = supplyIndex0[recipient]; // get last adjusted index0 for recipient
            uint256 _supplyIndex1 = supplyIndex1[recipient];
            uint256 _index0 = index0; // get global index0 for accumulated fees
            uint256 _index1 = index1;
            supplyIndex0[recipient] = _index0; // update user current position to global position
            supplyIndex1[recipient] = _index1;
            uint256 _delta0 = _index0 - _supplyIndex0; // see if there is any difference that need to be accrued
            uint256 _delta1 = _index1 - _supplyIndex1;
            if (_delta0 > 0) {
                uint256 _share = (_supplied * _delta0) / 1e18; // add accrued difference for each supplied token
                claimable0[recipient] += _share;
            }
            if (_delta1 > 0) {
                uint256 _share = (_supplied * _delta1) / 1e18;
                claimable1[recipient] += _share;
            }
        } else {
            supplyIndex0[recipient] = index0; // new users are set to the default global state
            supplyIndex1[recipient] = index1;
        }
    }

    /// @inheritdoc IPool
    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /// @dev update reserves and, on the first call per block, price accumulators
    function _update(uint256 balance0, uint256 balance1, uint256 _reserve0, uint256 _reserve1) internal {
        uint256 blockTimestamp = block.timestamp;
        uint256 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            reserve0CumulativeLast += _reserve0 * timeElapsed;
            reserve1CumulativeLast += _reserve1 * timeElapsed;
        }

        Observation memory _point = lastObservation();
        timeElapsed = blockTimestamp - _point.timestamp; // compare the last observation with current timestamp, if greater than 30 minutes, record a new event
        if (timeElapsed > periodSize) {
            observations.push(Observation(blockTimestamp, reserve0CumulativeLast, reserve1CumulativeLast));
        }
        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /// @inheritdoc IPool
    function currentCumulativePrices()
        public
        view
        returns (uint256 reserve0Cumulative, uint256 reserve1Cumulative, uint256 blockTimestamp)
    {
        blockTimestamp = block.timestamp;
        reserve0Cumulative = reserve0CumulativeLast;
        reserve1Cumulative = reserve1CumulativeLast;

        // if time has elapsed since the last update on the pool, mock the accumulated price values
        (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) = getReserves();
        if (_blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint256 timeElapsed = blockTimestamp - _blockTimestampLast;
            reserve0Cumulative += _reserve0 * timeElapsed;
            reserve1Cumulative += _reserve1 * timeElapsed;
        }
    }

    /// @inheritdoc IPool
    function quote(address tokenIn, uint256 amountIn, uint256 granularity) external view returns (uint256 amountOut) {
        uint256[] memory _prices = sample(tokenIn, amountIn, granularity, 1);
        uint256 priceAverageCumulative;
        uint256 _length = _prices.length;
        for (uint256 i = 0; i < _length; i++) {
            priceAverageCumulative += _prices[i];
        }
        return priceAverageCumulative / granularity;
    }

    /// @inheritdoc IPool
    function prices(address tokenIn, uint256 amountIn, uint256 points) external view returns (uint256[] memory) {
        return sample(tokenIn, amountIn, points, 1);
    }

    /// @inheritdoc IPool
    function sample(
        address tokenIn,
        uint256 amountIn,
        uint256 points,
        uint256 window
    ) public view returns (uint256[] memory) {
        uint256[] memory _prices = new uint256[](points);

        uint256 length = observations.length - 1;
        uint256 i = length - (points * window);
        uint256 nextIndex = 0;
        uint256 index = 0;

        for (; i < length; i += window) {
            nextIndex = i + window;
            uint256 timeElapsed = observations[nextIndex].timestamp - observations[i].timestamp;
            uint256 _reserve0 = (observations[nextIndex].reserve0Cumulative - observations[i].reserve0Cumulative) /
                timeElapsed;
            uint256 _reserve1 = (observations[nextIndex].reserve1Cumulative - observations[i].reserve1Cumulative) /
                timeElapsed;
            _prices[index] = _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
            // index < length; length cannot overflow
            unchecked {
                index = index + 1;
            }
        }
        return _prices;
    }

    /// @inheritdoc IPool
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        uint256 _balance0 = IERC20(token0).balanceOf(address(this));
        uint256 _balance1 = IERC20(token1).balanceOf(address(this));
        uint256 _amount0 = _balance0 - _reserve0;
        uint256 _amount1 = _balance1 - _reserve1;

        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(_amount0 * _amount1) - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens - cannot be address(0)
            if (stable) {
                if ((_amount0 * 1e18) / decimals0 != (_amount1 * 1e18) / decimals1) revert DepositsNotEqual();
                if (_k(_amount0, _amount1) <= MINIMUM_K) revert BelowMinimumK();
            }
        } else {
            liquidity = Math.min((_amount0 * _totalSupply) / _reserve0, (_amount1 * _totalSupply) / _reserve1);
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(_balance0, _balance1, _reserve0, _reserve1);
        emit Mint(_msgSender(), _amount0, _amount1);
    }

    /// @inheritdoc IPool
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        (address _token0, address _token1) = (token0, token1);
        uint256 _balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 _balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 _liquidity = balanceOf(address(this));

        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = (_liquidity * _balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (_liquidity * _balance1) / _totalSupply; // using balances ensures pro-rata distribution
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        _burn(address(this), _liquidity);
        IERC20(_token0).safeTransfer(to, amount0);
        IERC20(_token1).safeTransfer(to, amount1);
        _balance0 = IERC20(_token0).balanceOf(address(this));
        _balance1 = IERC20(_token1).balanceOf(address(this));

        _update(_balance0, _balance1, _reserve0, _reserve1);
        emit Burn(_msgSender(), to, amount0, amount1);
    }

    /// @inheritdoc IPool
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
        if (IPoolFactory(factory).isPaused()) revert IsPaused();
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert InsufficientLiquidity();

        uint256 _balance0;
        uint256 _balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            (address _token0, address _token1) = (token0, token1);
            if (to == _token0 || to == _token1) revert InvalidTo();
            if (amount0Out > 0) IERC20(_token0).safeTransfer(to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) IERC20(_token1).safeTransfer(to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IPoolCallee(to).hook(_msgSender(), amount0Out, amount1Out, data); // callback, used for flash loans
            _balance0 = IERC20(_token0).balanceOf(address(this));
            _balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = _balance0 > _reserve0 - amount0Out ? _balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = _balance1 > _reserve1 - amount1Out ? _balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            (address _token0, address _token1) = (token0, token1);
            if (amount0In > 0) _update0((amount0In * IPoolFactory(factory).getFee(address(this), stable)) / 10000); // accrue fees for token0 and move them out of pool
            if (amount1In > 0) _update1((amount1In * IPoolFactory(factory).getFee(address(this), stable)) / 10000); // accrue fees for token1 and move them out of pool
            _balance0 = IERC20(_token0).balanceOf(address(this)); // since we removed tokens, we need to reconfirm balances, can also simply use previous balance - amountIn/ 10000, but doing balanceOf again as safety check
            _balance1 = IERC20(_token1).balanceOf(address(this));
            // The curve, either x3y+y3x for stable pools, or x*y for volatile pools
            if (_k(_balance0, _balance1) < _k(_reserve0, _reserve1)) revert K();
        }

        _update(_balance0, _balance1, _reserve0, _reserve1);
        emit Swap(_msgSender(), to, amount0In, amount1In, amount0Out, amount1Out);
    }

    /// @inheritdoc IPool
    function skim(address to) external nonReentrant {
        (address _token0, address _token1) = (token0, token1);
        IERC20(_token0).safeTransfer(to, IERC20(_token0).balanceOf(address(this)) - (reserve0));
        IERC20(_token1).safeTransfer(to, IERC20(_token1).balanceOf(address(this)) - (reserve1));
    }

    /// @inheritdoc IPool
    function sync() external nonReentrant {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        uint256 _a = (x0 * y) / 1e18;
        uint256 _b = ((x0 * x0) / 1e18 + (y * y) / 1e18);
        return (_a * _b) / 1e18;
    }

    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }

    function _get_y(uint256 x0, uint256 xy, uint256 y) internal view returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 k = _f(x0, y);
            if (k < xy) {
                // there are two cases where dy == 0
                // case 1: The y is converged and we find the correct answer
                // case 2: _d(x0, y) is too large compare to (xy - k) and the rounding error
                //         screwed us.
                //         In this case, we need to increase y by 1
                uint256 dy = ((xy - k) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy) {
                        // We found the correct answer. Return y
                        return y;
                    }
                    if (_k(x0, y + 1) > xy) {
                        // If _k(x0, y + 1) > xy, then we are close to the correct answer.
                        // There's no closer answer than y + 1
                        return y + 1;
                    }
                    dy = 1;
                }
                y = y + dy;
            } else {
                uint256 dy = ((k - xy) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy || _f(x0, y - 1) < xy) {
                        // Likewise, if k == xy, we found the correct answer.
                        // If _f(x0, y - 1) < xy, then we are close to the correct answer.
                        // There's no closer answer than "y"
                        // It's worth mentioning that we need to find y where f(x0, y) >= xy
                        // As a result, we can't return y - 1 even it's closer to the correct answer
                        return y;
                    }
                    dy = 1;
                }
                y = y - dy;
            }
        }
        revert("!y");
    }

    /// @inheritdoc IPool
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        amountIn -= (amountIn * IPoolFactory(factory).getFee(address(this), stable)) / 10000; // remove fee from amount received
        return _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    function _getAmountOut(
        uint256 amountIn,
        address tokenIn,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256) {
        if (stable) {
            uint256 xy = _k(_reserve0, _reserve1);
            _reserve0 = (_reserve0 * 1e18) / decimals0;
            _reserve1 = (_reserve1 * 1e18) / decimals1;
            (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            amountIn = tokenIn == token0 ? (amountIn * 1e18) / decimals0 : (amountIn * 1e18) / decimals1;
            uint256 y = reserveB - _get_y(amountIn + reserveA, xy, reserveB);
            return (y * (tokenIn == token0 ? decimals1 : decimals0)) / 1e18;
        } else {
            (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            return (amountIn * reserveB) / (reserveA + amountIn);
        }
    }

    function _k(uint256 x, uint256 y) internal view returns (uint256) {
        if (stable) {
            uint256 _x = (x * 1e18) / decimals0;
            uint256 _y = (y * 1e18) / decimals1;
            uint256 _a = (_x * _y) / 1e18;
            uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
            return (_a * _b) / 1e18; // x3y+y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }

    /*
    @dev OZ inheritance overrides
    These are needed as _name and _symbol are set privately before
    logic is executed within the constructor to set _name and _symbol.
    */
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        _updateFor(from);
        _updateFor(to);
    }
}
