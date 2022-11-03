// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Math} from "./Math.sol";

interface IExchangeV2Callee {
    function exchangeV2Call(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external;
}

contract ExchangeV2 is ERC20("ExchangeV2", "V2", 18) {
    //
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    bool private isEntered;

    event Burn(address indexed sender, uint256 amount0, uint256 amount1);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);
    event Swap(address indexed sender, uint256 amount0Out, uint256 amount1Out, address indexed to);

    error AlreadyInitialized();
    error BalanceOverflow();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InsufficientLiquidityBurned();
    error InsufficientLiquidityMinted();
    error InsufficientOutputAmount();
    error InvalidK();
    error TransferFailed();

    modifier nonReentrant() {
        require(!isEntered);
        isEntered = true;

        _;

        isEntered = false;
    }

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, 0);
    }

    function mint(address _to) public {
        uint256 _balance0 = ERC20(token0).balanceOf(address(this));
        uint256 _balance1 = ERC20(token1).balanceOf(address(this));
        uint256 _amount0 = _balance0 - reserve0; // Considering tokens have already been sent to contract
        uint256 _amount1 = _balance1 - reserve1; // Considering tokens have already been sent to contract
        uint256 liquidity;
        if (totalSupply == 0) {
            liquidity = Math.sqrt(_amount1 * _amount0) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((_amount0 * totalSupply) / reserve0, (_amount1 * totalSupply) / reserve1);
        }
        if (liquidity <= 0) revert InsufficientLiquidityMinted();
        _mint(_to, liquidity);
        _update(_balance0, _balance1);
        emit Mint(_to, _amount0, _amount1);
    }

    function burn(address _to) public {
        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)]; // Amount of liquidity sent to Exchange
        uint256 amount0 = (liquidity * balance0) / totalSupply; // Calculate amt of token0 to be sent
        uint256 amount1 = (liquidity * balance1) / totalSupply; // Calculate amt of token1 to be sent
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        _burn(address(this), liquidity);
        _safeTransfer(token0, _to, amount0);
        _safeTransfer(token1, _to, amount1);
        balance0 = ERC20(token0).balanceOf(address(this));
        balance1 = ERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);
        emit Burn(_to, amount0, amount1);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) public nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) {
            revert InsufficientOutputAmount();
        }

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        if (amount0Out > reserve0_ || amount1Out > reserve1_) {
            revert InsufficientLiquidity();
        }

        // Optimistically send tokens to user
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);
        if (data.length > 0) {
            IExchangeV2Callee(to).exchangeV2Call(msg.sender, amount0Out, amount1Out, data);
        }

        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // Adjusted = balance before swap - swap fee; fee stays in the contract
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);

        if (balance0Adjusted * balance1Adjusted < uint256(reserve0_) * uint256(reserve1_) * (1000 ** 2)) {
            revert InvalidK();
        }

        _update(balance0, balance1);

        emit Swap(msg.sender, amount0Out, amount1Out, to);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }
}
