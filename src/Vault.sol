// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";

contract Vault is ERC4626 {
    using SafeERC20 for IERC20;


    address public owner;

    constructor(address _asset,
        string memory _name,
        string memory _symbol) ERC4626(ERC20(_asset), _name, _symbol) {
        owner = msg.sender;
    }

    function get(address token, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        // Logic to get tokens from the vault
        IERC20(token).safeTransfer(owner, amount);
    }

    function totalAssets() public view override returns (uint256) {
        return 0;
    }
}
