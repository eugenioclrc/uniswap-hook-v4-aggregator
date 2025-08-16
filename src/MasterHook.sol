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

    function _beforeSwap(
    address,
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata hookData
) internal override returns (bytes4, BeforeSwapDelta, uint24) {
    PoolId id = key.toId();

    (uint160 sqrtP,, ,) = poolManager.getSlot0(id);
    uint128 Lpool = poolManager.getLiquidity(id);

    // 1) Target price boundary (for a very tight JIT band at current price)
    int24 tick = TickMath.getTickAtSqrtPrice(sqrtP);
     tickLower = getLowerUsableTick(tick, key.tickSpacing);
     tickLower -= key.tickSpacing;
     tickUpper = tickLower + key.tickSpacing;

    uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
    uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);

    // 2) Estimate this-step swap out (lower bound; good enough to cap JIT)
    //    NOTE: computeSwapStep uses *current* liquidity; that's fine for a cap.
    (uint160 sqrtNext, uint256 stepIn, uint256 stepOut, ) =
        SwapMath.computeSwapStep(sqrtP, params.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1, Lpool, params.amountSpecified, key.fee);

    // 3) Read vault balances (caps)
    uint256 vault0 = key.currency0.balanceOf(address(vault));
    uint256 vault1 = key.currency1.balanceOf(address(vault));

    // 4) Decide caps for the *outgoing* side of the swap to avoid over-adding.
    //    We still pass both amounts into getLiquidityForAmounts so we never exceed vault funds on either side.
    uint256 cap0 = vault0;
    uint256 cap1 = vault1;
    if (params.zeroForOne) {
        // pool will pay out token1; don't try to supply more than stepOut from vault1
        if (cap1 > stepOut) cap1 = stepOut;
    } else {
        // pool will pay out token0
        if (cap0 > stepOut) cap0 = stepOut;
    }

    // Early exit if vault has nothing useful
    if (cap0 == 0 && cap1 == 0) {
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // 5) Max liquidity that fits those caps at *current* price
    //    This respects both side balances; it won't demand more than {cap0,cap1}
    liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
        sqrtP,
        sqrtA,
        sqrtB,
        cap0,
        cap1
    );

    if (liquidityDelta == 0) {
        // Not enough funds (or band too tight), skip JIT
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // 6) Add JIT liquidity
    (BalanceDelta delta, ) = poolManager.modifyLiquidity(
        key,
        ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(uint256(liquidityDelta)),
            salt: 0
        }),
        hookData
    );

    // 7) Settle EXACT owed amounts (negative deltas) from the vault
    int256 d0 = delta.amount0();
    int256 d1 = delta.amount1();

    if (d0 < 0) {
        uint256 owe0 = uint256(-d0);
        // by construction, owe0 <= cap0 <= vault0, so this cannot underfund
        vault.get(Currency.unwrap(key.currency0), owe0);
        key.currency0.settle(poolManager, address(this), owe0, false);
    }
    if (d1 < 0) {
        uint256 owe1 = uint256(-d1);
        // by construction, owe1 <= cap1 <= vault1
        vault.get(Currency.unwrap(key.currency1), owe1);
        key.currency1.settle(poolManager, address(this), owe1, false);
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
        if(liquidityDelta == 0) {
            // No JIT liquidity was added, nothing to do
            return (BaseHook.afterSwap.selector, 0);
        }

        // should i do this to collect fees?
        /*
        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: 0,
                salt: 0
            }),
            data
        );
        */

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
