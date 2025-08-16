// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/lib/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapMath} from "@uniswap/v4-periphery/lib/v4-core/src/libraries/SwapMath.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "lib/uniswap-hooks/src/utils/CurrencySettler.sol";

import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";

import {console} from "forge-std/console.sol";

import {Vault} from "./Vault.sol";

contract MasterHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    int24 transient tickUpper;
    int24 transient tickLower;
    uint128 transient liquidityDelta;

    Vault public vault;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        vault = new Vault();
    }

    function absoluteValue(int256 value) internal pure returns (uint256) {
        return value >= 0 ? uint256(value) : uint256(-value);
    }

    function getLowerUsableTick(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 intervals = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) intervals--; // round towards negative infinity
        return intervals * tickSpacing;
    }

    function getUpperUsableTick(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 intervals = tick / tickSpacing;
        // If the tick is not perfectly aligned, move up to the next interval
        if (tick % tickSpacing != 0) {
            intervals++;
        }
        return intervals * tickSpacing;
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

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata swapParams, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        uint128 liquidity = poolManager.getLiquidity(key.toId());
        uint24 feePips = key.fee; // Retrieve the fee

        // Set target price for the swap direction
        uint160 sqrtPriceTargetX96 = swapParams.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        // Use computeSwapStep to get the next price, amounts, and fees
        (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut,) =
            SwapMath.computeSwapStep(sqrtPriceX96, sqrtPriceTargetX96, liquidity, swapParams.amountSpecified, feePips);

        // Convert amountSpecified to absolute value to avoid negative amounts for JIT
        uint256 amount = absoluteValue(swapParams.amountSpecified);

        // Calculate new tick after swap
        int24 newTick = TickMath.getTickAtSqrtPrice(sqrtPriceNextX96); // Get the higher tick range

        // Ensure tick spacing for liquidity range
        tickUpper = getLowerUsableTick(newTick, key.tickSpacing);
        tickLower = tickUpper > 0 ? -tickUpper : tickUpper + tickUpper;

        // Get sqrt prices at the tick boundaries
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // Calculate the liquidity amount to add
        liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceAtTickLower, sqrtPriceAtTickUpper, amount);

        console.log("Liquidity delta:");
        console.logUint(sqrtPriceAtTickLower);
        console.logUint(sqrtPriceAtTickUpper);

        // Modify liquidity in the pool
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: 0
            }),
            hookData
        );

        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();
        console.logInt(delta0);
        console.logInt(delta1);
        if (delta0 < 0) {
            // Withdraw tokens from JIT address (pool) to contract
            vault.get(Currency.unwrap(key.currency0), uint256(-delta0));

            key.currency0.settle(poolManager, address(this), uint256(-delta0), false);
        }
        if (delta1 < 0) {
            // Withdraw tokens from JIT address (pool) to contract
            vault.get(Currency.unwrap(key.currency1), uint256(-delta1));

            key.currency1.settle(poolManager, address(this), uint256(-delta1), false);
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) internal override returns (bytes4, int128) {
        (BalanceDelta _delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -int256(uint256(liquidityDelta)),
                salt: 0
            }),
            data
        );
        int256 delta0 = _delta.amount0();
        int256 delta1 = _delta.amount1();

        if (delta0 > 0) {
            key.currency0.take(poolManager, address(vault), uint256(delta0), false);
        }
        if (delta1 > 0) {
            key.currency1.take(poolManager, address(vault), uint256(delta1), false);
        }

        return (BaseHook.afterSwap.selector, 0);
    }
}
