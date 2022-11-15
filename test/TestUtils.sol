// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "v3/interfaces/IUniswapV3Pool.sol";

abstract contract TestUtils {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    function encodeError(string memory error) internal pure returns (bytes memory encoded) {
        encoded = abi.encodeWithSignature(error);
    }

    function encodeExtra(address token0_, address token1_, address payer) internal pure returns (bytes memory) {
        return abi.encode(IUniswapV3Pool.CallbackData({token0: token0_, token1: token1_, payer: payer}));
    }
}
