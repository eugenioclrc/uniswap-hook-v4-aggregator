// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";
import {AggregatorV3Interface} from "lib/chainlink-evm/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IWstETH} from "@uniswap/v4-periphery/src/interfaces/external/IWstETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {IPool} from "./interfaces/aave-v3-IPool.sol";

import {console} from "forge-std/console.sol";

contract Vault is ERC4626 {
    using SafeTransferLib for ERC20;

    // WETH
    address constant t0 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    ERC20 immutable at0Supply; // aave supply WETH
    // wstETH (Lido Wrapped stETH)
    address constant t1 = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    ERC20 immutable at1Supply; // aave supply wstETH
    // rETH (Rocket Pool ETH)
    address constant t2 = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    ERC20 immutable at2Supply; // aave supply rETH
    // weETH (Ether.fi Wrapped eETH)
    address constant t3 = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    ERC20 immutable at3Supply; // aave supply weETH

    // oracles
    AggregatorV3Interface constant oracleSTETH_ETH = AggregatorV3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
    AggregatorV3Interface constant oracleRETH_ETH = AggregatorV3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0);
    AggregatorV3Interface constant oracleWEETH_ETH = AggregatorV3Interface(0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22);
    AggregatorV3Interface constant oracleETH_USD = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    address public _owner;

    IPool public immutable POOL_AAVE = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // Aave V3 Pool

    constructor(address _asset, string memory _name, string memory _symbol) ERC4626(ERC20(_asset), _name, _symbol) {
        _owner = msg.sender;

        ERC20(t0).approve(address(POOL_AAVE), type(uint256).max);
        ERC20(t1).approve(address(POOL_AAVE), type(uint256).max);
        ERC20(t2).approve(address(POOL_AAVE), type(uint256).max);
        ERC20(t3).approve(address(POOL_AAVE), type(uint256).max);

        IPool.ReserveData memory _data = POOL_AAVE.getReserveData(t0);
        at0Supply = ERC20(_data.aTokenAddress);
        _data = POOL_AAVE.getReserveData(t1);
        at1Supply = ERC20(_data.aTokenAddress);
        _data = POOL_AAVE.getReserveData(t2);
        at2Supply = ERC20(_data.aTokenAddress);
        _data = POOL_AAVE.getReserveData(t3);
        at3Supply = ERC20(_data.aTokenAddress);
    }

    function get(address token, uint256 amount) external {
        require(msg.sender == _owner, "only owner");
        // Logic to get tokens from the vault
        ERC20(token).safeTransfer(_owner, amount);
    }

    function supply(address token) external {
        uint256 _balance = ERC20(token).balanceOf(address(this));
        if (_balance == 0) return;
        // SUPPLY
        POOL_AAVE.supply({asset: token, amount: _balance, onBehalfOf: address(this), referralCode: 0});
    }

    function afterDeposit(uint256 assets, uint256 shares) internal override {
        // SUPPLY WETH
        POOL_AAVE.supply({
            asset: t0,
            amount: ERC20(t0).balanceOf(address(this)),
            onBehalfOf: address(this),
            referralCode: 0
        });
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        _transferAssets(owner, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        _transferAssets(receiver, assets);
    }

    function _transferAssets(address receiver, uint256 assets) internal {
        //asset.safeTransfer(receiver, assets);
        uint256 balanceT0 = at0Supply.balanceOf(address(this));
        uint256 balanceT1 = get_wstETH_ETH();
        uint256 balanceT2 = getNormalized(address(at2Supply), oracleRETH_ETH);
        uint256 balanceT3 = getNormalized(address(at3Supply), oracleWEETH_ETH);

        console.log("contratto T2", at2Supply.balanceOf(address(this)));

        uint256 _totalAssets = totalAssets();

        balanceT0 = (assets * balanceT0) / _totalAssets;
        if(balanceT0 > 0) POOL_AAVE.withdraw(t0, balanceT0, receiver);

        balanceT1 = (assets * balanceT1) / _totalAssets;
        console.log("wstETH transfer", balanceT1);
        if(balanceT1 > 0) {
            uint256 price = getChainlinkDataFeedLatestAnswer(oracleSTETH_ETH);
            balanceT1 = (balanceT1 * 10 ** 18) / price;
            POOL_AAVE.withdraw(t1, IWstETH(t1).getStETHByWstETH(balanceT1), receiver);
        }

        balanceT2 = (assets * balanceT2) / _totalAssets;
        if(balanceT2 > 0) {
            uint256 price = getChainlinkDataFeedLatestAnswer(oracleRETH_ETH);
            POOL_AAVE.withdraw(t2, (balanceT2 * 10 ** 18) / price, receiver);
        }

        balanceT3 = (assets * balanceT3) / _totalAssets;
        if(balanceT3 > 0) {
            uint256 price = getChainlinkDataFeedLatestAnswer(oracleWEETH_ETH);
            POOL_AAVE.withdraw(t3, (balanceT3 * 10 ** 18) / price, receiver);
        }
    }

    function totalAssets() public view override returns (uint256) {
       uint256 _totalAssets = 
       at0Supply.balanceOf(address(this)) +
       get_wstETH_ETH() +
       getNormalized(address(at2Supply), oracleRETH_ETH) +
       getNormalized(address(at3Supply), oracleWEETH_ETH);

       return _totalAssets;
    }

    function get_wstETH_ETH() internal view returns (uint256) {
        uint256 amount = at1Supply.balanceOf(address(this));
        uint256 price = getChainlinkDataFeedLatestAnswer(oracleSTETH_ETH);
        return IWstETH(t1).getStETHByWstETH(amount) * price / 10 ** 18;
    }

    function getNormalized(address token, AggregatorV3Interface oracle) internal view returns (uint256) {
        console.log("token balance", token) ;

        uint256 amount = IERC20(token).balanceOf(address(this));
        console.log(amount);
        console.log("*********");
        uint256 price = getChainlinkDataFeedLatestAnswer(oracle);
        return amount * price / 10 ** 18;
    }

    function getChainlinkDataFeedLatestAnswer(AggregatorV3Interface dataFeed) internal view returns (uint256) {
        // prettier-ignore
        (
            /* uint80 roundId */
            ,
            int256 answer,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();

        // todo check answers

        return uint256(answer);
    }
}
