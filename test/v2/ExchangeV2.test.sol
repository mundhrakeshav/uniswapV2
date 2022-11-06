// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {Math} from "v2/libraries/Math.sol";
import {ExchangeV2} from "v2/ExchangeV2.sol";
import {ERC20Mintable} from "./ERC20Mintable.sol";
import {console} from "forge-std/console.sol";

contract ExchangeV2Test is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    ExchangeV2 pair;
    address user1 = address(1);

    function setUp() public {
        // vm.deal(null, null);
        startHoax(user1);
        token0 = new ERC20Mintable("Token A", "TKNA");
        token1 = new ERC20Mintable("Token B", "TKNB");
        pair = new ExchangeV2(address(token0), address(token1));
        token0.mint(user1, 10 ether);
        token1.mint(user1, 10 ether);
    }

    function assertReserves(uint112 expectedReserve0, uint112 expectedReserve1) internal {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, expectedReserve0, "unexpected reserve0");
        assertEq(reserve1, expectedReserve1, "unexpected reserve1");
    }

    function testMintBootstrap() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(user1);

        assertEq(pair.balanceOf(user1), 1 ether - 1000); // 1 ether of LP-tokens is issued and we get 1 ether - 1000 (minus the minimal liquidity)
        assertReserves(1 ether, 1 ether);
        assertEq(pair.totalSupply(), 1 ether);
    }

    function testMintWhenTheresLiquidity() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(user1); // + 1 LP

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 2 ether);

        pair.mint(user1); // + 2 LP

        assertEq(pair.balanceOf(user1), 3 ether - 1000);
        assertEq(pair.totalSupply(), 3 ether);
        assertReserves(3 ether, 3 ether);
    }

    function testMintUnbalanced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(user1); // + 1 LP
        assertEq(pair.balanceOf(user1), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(user1); // + 1 LP
        assertEq(pair.balanceOf(user1), 2 ether - 1000);
        assertReserves(3 ether, 2 ether);
    }

    function testBurn() public {
        // Mint Balanced
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(user1);

        // Burn total liquidity
        uint256 liquidity = pair.balanceOf(user1);
        pair.transfer(address(pair), liquidity);
        pair.burn(user1);

        // Pool returns to its uninitialized state except the minimum liquidity that was sent to the zero address– it cannot be claimed.
        assertEq(pair.balanceOf(user1), 0); // Liquidity Burned
        assertReserves(1000, 1000); // MINIMUM_LIQUIDITY, burned
        assertEq(pair.totalSupply(), 1000); // MINIMUM_LIQUIDITY, burned
        assertEq(pair.balanceOf(address(0)), 1000); // MINIMUM_LIQUIDITY, burned
        assertEq(token0.balanceOf(user1), 10 ether - 1000); // Initially 10 Eth were minted and 1000 tokens have been locked in pair
        assertEq(token1.balanceOf(user1), 10 ether - 1000);
    }

    function testBurnUnbalanced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(user1);

        // Unbalanced Mint
        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(user1); // + 1 LP
        // Reserves
        // Token0 = 3
        // Token1 = 2
        // Burn
        pair.transfer(address(pair), pair.balanceOf(user1));
        pair.burn(user1);

        assertEq(pair.balanceOf(user1), 0);
        assertReserves(1500, 1000); // As we deposited Unbalanced liquidity, the liquidity was calculated wrt the min value. We lost 500 tokens
        assertEq(pair.totalSupply(), 1000);
        assertEq(token0.balanceOf(user1), 10 ether - 1500);
        assertEq(token1.balanceOf(user1), 10 ether - 1000);
    }
}
