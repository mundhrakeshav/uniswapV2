// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Tick} from "./lib/Tick.sol";
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
        amount1 = Math.calcAmount0Delta(
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

    function swap(address recipient, bytes calldata data) public returns (int256 amount0, int256 amount1) {
        // Hardcoded Values calculated from ./unimath.py
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;
        amount0 = -0.008396714242162444 ether; // -ve as it goes out of system
        amount1 = 42 ether;

        /*
            * update the current tick and sqrtP since trading affects the current price:
        */
        (slot0.tick, slot0.sqrtPriceX96) = (nextTick, nextPrice);

        IERC20(token0).transfer(recipient, uint256(-amount0));

        uint256 balance1Before = balance1();
        /* 
            * The caller is expected to implement uniswapV3SwapCallback and transfer input tokens to the Pool contract in this function.
        */
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);

        if (balance1Before + uint256(amount1) > balance1()) {
            revert InsufficientInputAmount();
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
