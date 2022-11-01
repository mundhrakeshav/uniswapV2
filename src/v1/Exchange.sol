// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract Exchange is ERC20("Swap", "SWAP", 18) {
    address public immutable tokenAddress;

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Address 0");
        tokenAddress = _tokenAddress;
    }

    function getReserve() public view returns (uint256) {
        return ERC20(tokenAddress).balanceOf(address(this));
    }

    function ethToTokenSwap(uint256 _minTokens) public payable {
        uint256 tokenReserve = getReserve();
        uint256 tokensBought = getOutAmount(msg.value, address(this).balance - msg.value, tokenReserve);
        require(tokensBought >= _minTokens, "insufficient output");
        ERC20(tokenAddress).transfer(msg.sender, tokensBought);
    }

    function tokenToEthSwap(uint256 _tokensSold, uint256 _minEth) public {
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getOutAmount(_tokensSold, tokenReserve, address(this).balance);
        require(ethBought >= _minEth, "insufficient output");
        ERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokensSold);
        payable(msg.sender).transfer(ethBought);
    }

    function getOutAmount(uint256 inAmount, uint256 inReserve, uint256 outReserve) private pure returns (uint256) {
        require(inReserve > 0 && outReserve > 0, "!Reserves");
        uint256 inputAmountWithFee = inAmount * 99;
        uint256 numerator = inputAmountWithFee * outReserve;
        uint256 denominator = (inReserve * 100) + inputAmountWithFee;
        return numerator / denominator;
        // return (inAmount * outReserve) / (inReserve + inAmount);
    }

    function addLiquidity(uint256 _tokenAmount) public payable {
        if (getReserve() == 0) {
            ERC20 token = ERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), _tokenAmount);
            uint256 liquidity = address(this).balance;
            _mint(msg.sender, liquidity);
        } else {
            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenAmount = (msg.value * getReserve()) / ethReserve;
            require(_tokenAmount >= tokenAmount, "insufficient token");
            ERC20 token = ERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount);
            uint256 liquidity = (totalSupply * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);
        }
    }

    function removeLiquidity(uint256 _amount) public returns (uint256, uint256) {
        require(_amount > 0, "invalid amount");
        uint256 ethAmount = (address(this).balance * _amount) / totalSupply;
        uint256 tokenAmount = (getReserve() * _amount) / totalSupply;
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(ethAmount);
        ERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        return (ethAmount, tokenAmount);
    }
}
