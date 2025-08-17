// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";
import {AggregatorV3Interface} from "lib/chainlink-evm/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Vault is ERC4626 {
    using SafeERC20 for IERC20;

    // WETH
    address constant t0 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // wstETH (Lido Wrapped stETH)
    address constant t1 = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    // rETH (Rocket Pool ETH)
    address constant t2 = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    // weETH (Ether.fi Wrapped eETH)
    address constant t3 = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    // oracles
    address constant oracleSTETH_ETH = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant oracleRETH_ETH = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant oracleWEETH_ETH = 0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22;

    address public owner;

    constructor(address _asset, string memory _name, string memory _symbol) ERC4626(ERC20(_asset), _name, _symbol) {
        owner = msg.sender;
    }

    function get(address token, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        // Logic to get tokens from the vault
        IERC20(token).safeTransfer(owner, amount);
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(t0).balanceOf(address(this)) + 
            get_wstETH_ETH(IERC20(t1).balanceOf(address(this))) + 
            get_RETH_ETH(IERC20(t2).balanceOf(address(this))) + 
            get_weETH_ETH(IERC20(t3).balanceOf(address(this)));
    }

    function get_wstETH_ETH(uint256 amount) internal view returns (uint256) {
        // wstETH to STETH
        amount = t1.getStETHByWstETH(amount);
        // STETH to ETH
        uint256 price = getChainlinkDataFeedLatestAnswer(dataFeed_STETH_ETH);

        return amount * price;
    }

    function get_RETH_ETH(uint256 amount) internal view returns (uint256) {
        uint256 price = getChainlinkDataFeedLatestAnswer(dataFeed_STETH_ETH);

        return amount * price;
    }

    function get_weETH_ETH(uint256 amount) internal view returns (uint256) {
        uint256 price = getChainlinkDataFeedLatestAnswer(dataFeed_STETH_ETH);

        return amount * price;
    }

    function getChainlinkDataFeedLatestAnswer(AggregatorV3Interface dataFeed) internal view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
     
        return answer;
    }
}
