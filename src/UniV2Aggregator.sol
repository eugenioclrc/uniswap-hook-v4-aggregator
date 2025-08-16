// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

import {IUniswapV2Factory} from "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract UniV2Aggregator is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    IUniswapV2Factory public factory;

    // TODO this should be a hook parameter
    uint256 v2ShareBips = 1000;
    address transient _pair;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    // todo admin ADD ACCESS CONTROL / MAKE IT IMMUTABLE
    function setFactory(IUniswapV2Factory _factory) external {
        factory = _factory;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata swapData, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);

        // must have a V2 pair
        _pair = factory.getPair(t0, t1);
        if (_pair == address(0)) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // figure input token for this swap direction
        address tokenIn  = swapData.zeroForOne ? t0 : t1;

        uint256 amountIn = uint256(int256(swapData.amountSpecified)); // positive
        uint256 slice = (amountIn * v2ShareBips) / 10_000; // 10_000 = BPS
        if (slice == 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Reduce the v4 specified amount by `slice` (negative specified delta)
        // Entitles the hook to settle `slice` of tokenIn later via take().
        int128 specifiedDelta = -int128(int256(slice));
        BeforeSwapDelta delta = toBeforeSwapDelta(specifiedDelta, 0);

        return (BaseHook.beforeSwap.selector, delta, 0); // no fee override
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
         // _pair is setted in the `_beforeSwap`
        if (_pair == address(0)) {
            return (BaseHook.afterSwap.selector, 0);
        }


        return (BaseHook.afterSwap.selector, 0);
    }
}
