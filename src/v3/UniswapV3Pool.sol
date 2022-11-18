// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Tick} from "./lib/Tick.sol";
import {SwapMath} from "./lib/SwapMath.sol";
import {Math} from "./lib/Math.sol";
import {TickMath} from "./lib/TickMath.sol";
import {TickBitmap} from "./lib/TickBitmap.sol";
import {Position} from "./lib/Position.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IUniswapV3MintCallback} from "./interfaces/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "./interfaces/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";

contract UniswapV3Pool is IUniswapV3Pool {
    //
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using TickBitmap for mapping(int16 => uint256);

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    Slot0 public slot0;

    // Amount of liquidity, L.
    uint128 public liquidity;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;
    //Bitmap
    mapping(int16 => uint256) public tickBitmap;

    constructor(address token0_, address token1_, uint160 sqrtPriceX96, int24 tick) {
        token0 = token0_;
        token1 = token1_;

        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // Checks
        if (lowerTick >= upperTick || lowerTick < TickMath.MIN_TICK || upperTick > TickMath.MAX_TICK) {
            revert InvalidTickRange();
        }
        if (amount == 0) revert ZeroLiquidity();

        // Update upper and lower Ticks
        bool _flippedLower = ticks.update(lowerTick, amount);
        bool _flippedUpper = ticks.update(upperTick, amount);

        if (_flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }

        if (_flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }

        // Get position for those owner and desired ticks
        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        // Update Position
        position.update(amount);

        Slot0 memory _slot0 = slot0;

        amount0 = Math.calcAmount0Delta(
            TickMath.getSqrtRatioAtTick(_slot0.tick), TickMath.getSqrtRatioAtTick(upperTick), amount
        );
        amount1 = Math.calcAmount1Delta(
            TickMath.getSqrtRatioAtTick(_slot0.tick), TickMath.getSqrtRatioAtTick(lowerTick), amount
        );

        liquidity += uint128(amount);

        uint256 balance0Before;
        uint256 balance1Before;

        // record current token balances
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        /* 
        * The caller is expected to implement uniswapV3MintCallback and transfer tokens to the Pool contract in this function. 
        */
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);

        // Check if amount0 and amount1 have been transferred to the contract
        /* 
            * we require pool balance increase by at least amount0 and amount1 respectively–this would mean the caller has transferred tokens to the pool. 
         */

        if (amount0 > 0 && balance0Before + amount0 > balance0()) {
            revert InsufficientInputAmount();
        }

        if (amount1 > 0 && balance1Before + amount1 > balance1()) {
            revert InsufficientInputAmount();
        }

        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    function swap(address recipient, bool _zeroForOne, uint256 _amountSpecified, bytes calldata data)
        public
        returns (int256 amount0, int256 amount1)
    {
        Slot0 memory _slot0 = slot0;

        SwapState memory _swapState = SwapState({
            amountSpecifiedRemaining: _amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: _slot0.sqrtPriceX96,
            tick: _slot0.tick
        });

        while (_swapState.amountSpecifiedRemaining > 0) {
            StepState memory _step;
            _step.sqrtPriceStartX96 = _swapState.sqrtPriceX96;
            (_step.nextTick,) = tickBitmap.nextInitializedTickWithinOneWord(_swapState.tick, 1, _zeroForOne);
            _step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(_step.nextTick);
            
            (_swapState.sqrtPriceX96, _step.amountIn, _step.amountOut) = SwapMath.computeSwapStep(
                _step.sqrtPriceStartX96, _step.sqrtPriceNextX96, liquidity, _swapState.amountSpecifiedRemaining
            );
            _swapState.amountSpecifiedRemaining -= _step.amountIn;
            _swapState.amountCalculated += _step.amountOut;
            _swapState.tick = TickMath.getTickAtSqrtRatio(_swapState.sqrtPriceX96);
        }

        /*
            * update the current tick and sqrtP since trading affects the current price:
        */
        if (_swapState.tick != _slot0.tick) {
            (slot0.tick, slot0.sqrtPriceX96) = (_swapState.tick, _swapState.sqrtPriceX96);
        }

        (amount0, amount1) = _zeroForOne
            ? (int256(_amountSpecified - _swapState.amountSpecifiedRemaining), -int256(_swapState.amountCalculated))
            : (-int256(_swapState.amountCalculated), int256(_amountSpecified - _swapState.amountSpecifiedRemaining));

        if (_zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));
            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            if (balance0Before + uint256(amount0) > balance0()) {
                revert InsufficientInputAmount();
            }
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            if (balance1Before + uint256(amount1) > balance1()) {
                revert InsufficientInputAmount();
            }
        }

        emit Swap(msg.sender, recipient, amount0, amount1, slot0.sqrtPriceX96, liquidity, slot0.tick);
    }

    /*
    !!! INTERNAL
    */
    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }
}
