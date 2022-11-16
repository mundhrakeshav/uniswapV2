// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Tick} from "./lib/Tick.sol";
import {TickMath} from "./lib/TickMath.sol";
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

    constructor(address token0_, address token1_, uint160 sqrtPriceX96, int24 tick) {
        token0 = token0_;
        token1 = token1_;

        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    //1.  a user specifies a price range and an amount of liquidity;
    //2.  the contract updates the ticks and positions mappings;
    //3.  the contract calculates token amounts the user must send (we’ll pre-calculate and hard code them);
    //4.  the contract takes tokens from the user and verifies that correct amounts were set.

    // user specifies LL, not actual token amounts.
    /// @param amount = liquidity
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
        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        // Get position for those owner and desired ticks
        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        // Update Position
        position.update(amount);

        amount0 = 0.99897661834742528 ether; //! TODO: replace with calculation
        amount1 = 5000 ether; //! TODO: replace with calculation

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
