// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

library Tick {
    struct Info {
        bool initialized;
        uint128 liquidity;
    }

    function update(mapping(int24 => Tick.Info) storage self, int24 tick, uint128 liquidityDelta) internal {
        // Get the TickInfo referenced from mapping tick => tickInfo
        Tick.Info storage tickInfo = self[tick];

        // Calculate before and after liquidity
        uint128 liquidityBefore = tickInfo.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;

        // Initialized if not initialized
        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }

        // Set new liquidity
        tickInfo.liquidity = liquidityAfter;
    }
}
