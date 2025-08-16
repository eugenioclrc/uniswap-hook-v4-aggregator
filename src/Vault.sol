// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vault {
    using SafeERC20 for IERC20;

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function get(address token, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        // Logic to get tokens from the vault
        IERC20(token).safeTransfer(owner, amount);
    }
}
