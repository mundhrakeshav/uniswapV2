// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {TestUtils} from "./TestUtils.sol";
import {Math} from "v2/libraries/Math.sol";
import {UniswapV3Pool} from "v3/UniswapV3Pool.sol";
import {IUniswapV3Pool} from "v3/interfaces/IUniswapV3Pool.sol";
import {ERC20Mintable} from "./ERC20Mintable.sol";

contract UniswapV3Test is Test, TestUtils {
    ERC20Mintable weth;
    ERC20Mintable usdc;
    UniswapV3Pool pool;

    bool transferInMintCallback;
    bool transferInSwapCallback;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiqudity;
    }

    function setUp() public {
        weth = new ERC20Mintable("W-Ether", "WETH");
        usdc = new ERC20Mintable("USDC", "USDC");
    }

    function testMintV3Success() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiqudity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 expectedAmount0 = 0.99897661834742528 ether; // Because we use the smaller L
        uint256 expectedAmount1 = 5000 ether;
        // Check balances
        assertEq(poolBalance0, expectedAmount0, "Incorrect weth deposited amount");
        assertEq(poolBalance1, expectedAmount1, "Incorrect usdc deposited amount");
        assertEq(weth.balanceOf(address(pool)), expectedAmount0);
        assertEq(usdc.balanceOf(address(pool)), expectedAmount1);

        // Check Positions
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), params.lowerTick, params.upperTick));
        assertEq(params.liquidity, pool.positions(positionKey));

        // Check Ticks
        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(params.lowerTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);
        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        // Check Vars
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, params.currentSqrtP, "invalid current sqrtP");
        assertEq(tick, params.currentTick, "invalid current tick");
        assertEq(pool.liquidity(), params.liquidity, "invalid current liquidity");
    }

    function testMintV3InvalidTickRangeLower() public {
        pool = new UniswapV3Pool(
            address(weth),
            address(usdc),
            uint160(1),
            0
        );

        vm.expectRevert(encodeError("InvalidTickRange()"));
        pool.mint(address(this), MIN_TICK - 1, 0, 0, "");
    }

    function testMintV3InvalidTickRangeUpper() public {
        pool = new UniswapV3Pool(
            address(weth),
            address(usdc),
            uint160(1),
            0
        );

        vm.expectRevert(encodeError("InvalidTickRange()"));
        pool.mint(address(this), 0, MAX_TICK + 1, 0, "");
    }

    function testMintV3ZeroLiquidity() public {
        pool = new UniswapV3Pool(
            address(weth),
            address(usdc),
            uint160(1),
            0
        );

        vm.expectRevert(encodeError("ZeroLiquidity()"));
        pool.mint(address(this), 0, 1, 0, "");
    }

    function testMintV3InsufficientTokenBalance() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 0,
            usdcBalance: 0,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: false,
            transferInSwapCallback: true,
            mintLiqudity: false
        });
        setupTestCase(params);

        vm.expectRevert(encodeError("InsufficientInputAmount()"));
        pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, "");
    }

    function testSwapV3BuyEth() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240, // sqrtP(5000)
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiqudity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        usdc.mint(address(this), 42 ether);
        int256 userBalance0Before = int256(weth.balanceOf(address(this)));
        int256 userBalance1Before = int256(usdc.balanceOf(address(this)));
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this), "");

        // Check amount Delta
        assertEq(amount0Delta, -0.008396714242162444 ether, "invalid ETH out");
        assertEq(amount1Delta, 42 ether, "invalid USDC in");

        assertEq(weth.balanceOf(address(this)), uint256(userBalance0Before - amount0Delta), "invalid user ETH balance");
        assertEq(usdc.balanceOf(address(this)), uint256(userBalance1Before - amount1Delta), "invalid user USDC balance");

        assertEq(
            weth.balanceOf(address(pool)), uint256(int256(poolBalance0) + amount0Delta), "invalid pool ETH balance"
        );
        assertEq(
            usdc.balanceOf(address(pool)), uint256(int256(poolBalance1) + amount1Delta), "invalid pool USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5604469350942327889444743441197, "invalid current sqrtP");
        assertEq(tick, 85184, "invalid current tick");
        assertEq(pool.liquidity(), 1517882343751509868544, "invalid current liquidity");
    }

    function testSwapV3InsufficientInputAmount() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: false,
            mintLiqudity: true
        });
        setupTestCase(params);
        usdc.mint(address(this), 42 ether);

        vm.expectRevert(encodeError("InsufficientInputAmount()"));
        pool.swap(address(this), "");
    }

    /*
    ---
       !! Internal
    ---
    */

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata) public {
        if (transferInSwapCallback) {
            if (amount0 > 0) {
                weth.transfer(msg.sender, uint256(amount0));
            }
            if (amount1 > 0) {
                usdc.transfer(msg.sender, uint256(amount1));
            }
        }
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) public {
        // IUniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));

        if (transferInMintCallback) {
            weth.transfer(msg.sender, amount0);
            usdc.transfer(msg.sender, amount1);
        }
    }

    function setupTestCase(TestCaseParams memory params)
        internal
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        // Mint tokens to address(this)
        weth.mint(address(this), params.wethBalance);
        usdc.mint(address(this), params.usdcBalance);

        // Create new Uniswap pool
        pool = new UniswapV3Pool(
            address(weth),
            address(usdc),
            params.currentSqrtP,
            params.currentTick
        );

        transferInMintCallback = params.transferInMintCallback;
        transferInSwapCallback = params.transferInSwapCallback;



        // If mintLiquidity is set to true call mint
        if (params.mintLiqudity) {
            (poolBalance0, poolBalance1) =
                pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, "");
        }
        // Set transferInMintCallback
    }
}
