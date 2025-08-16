// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract MockWeETH is ERC20 {
    constructor() ERC20("Wrapped eETH", "weETH", 18) {}

    function deposit(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
