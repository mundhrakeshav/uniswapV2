// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./Math.sol";

library SwapMath {
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut) {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
        // SQRT Price Target
        sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(sqrtPriceCurrentX96, liquidity, amountRemaining, zeroForOne);

        // Δx and Δy can be calculated using SQRTPriceTarget SQRTPriceTargetNext and Liquidity
        amountIn = Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity);
        amountOut = Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity);

        if (!zeroForOne) {
            (amountIn, amountOut) = (amountOut, amountIn);
        }
    }
}
