// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

library FixedPointMath {
    // FixedPoint Number with range [0, 2**112 - 1]
    // FixedPoint Number with precison 1/ 2**112
    // First 112 bits for Integer
    // Last 112 bits for fraction

    uint8 constant RESOLUTION = 112;

    struct UQ112x112 {
        uint224 value;
    }

    // can only encode 112 bits
    function encode(uint112 _num) external pure returns (UQ112x112 memory) {
        return UQ112x112(uint224(_num) << RESOLUTION);
    }

    function decode(UQ112x112 calldata _num) external pure returns (uint112) {
        return uint112(_num.value >> RESOLUTION);
    }
}
