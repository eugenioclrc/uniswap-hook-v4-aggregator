// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract MockWstETH is ERC20 {
    constructor() ERC20("Wrapped stETH", "wstETH", 18) {}

    function getStETHByWstETH(uint256 _wstETHAmount) public pure returns (uint256) {
        if (_wstETHAmount == 0) return 0;

        uint256 EXCHANGE_RATE = 11e17;
        return (_wstETHAmount * EXCHANGE_RATE) / 1e18;
    }
}
