// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Tick} from "./lib/Tick.sol";
import {Position} from "./lib/Position.sol";

contract UniswapV3Pool {
    //
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    // Packing variables that are read together
    struct Slot0 {
        // Current sqrt(P)
        uint160 sqrtPriceX96;
        // Current tick
        int24 tick;
    }

    Slot0 public slot0;

    // Amount of liquidity, L.
    uint128 public liquidity;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;

    // Errors
    error InvalidTickRange();
    error ZeroLiquidity();

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
    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // Checks
        if (lowerTick >= upperTick || lowerTick < MIN_TICK || upperTick > MAX_TICK) revert InvalidTickRange();
        if (amount == 0) revert ZeroLiquidity();

        // Update upper and lower Ticks
        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        // Get position for those owner and desired ticks
        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        // Update Position
        position.update(amount);
    }
}
