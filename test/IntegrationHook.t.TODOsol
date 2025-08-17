// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";

import {MasterHook} from "../src/MasterHook.sol";

import {console} from "forge-std/console.sol";

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

contract IntegrationHookTest is Test {
    IPermit2 constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IPoolManager constant poolManager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IPositionManager constant positionManager = IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    IUniswapV4Router04 constant swapRouter = IUniswapV4Router04(payable(0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af));

    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    MasterHook hook;
    PoolId poolId;

    address user = makeAddr("user");

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // use anvil --rpc-url https://eth.llamarpc.com`
        vm.createSelectFork("http://127.0.0.1:8545");

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), /*CREATE2_FACTORY*/ flags, type(MasterHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        MasterHook masterHook = new MasterHook{salt: salt}(poolManager);
        hook = masterHook;

        // VALID TOKENS
        // WETH
        address t0 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        // wstETH (Lido Wrapped stETH)
        address t1 = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        // rETH (Rocket Pool ETH)
        address t2 = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        // weETH (Ether.fi Wrapped eETH)
        address t3 = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

        setupApproves(t0);
        setupApproves(t1);
        setupApproves(t2);
        setupApproves(t3);

        setupPool(t0, t1);
        setupPool(t0, t2);
        setupPool(t0, t3);
        setupPool(t1, t2);
        setupPool(t1, t3);
        setupPool(t2, t3);

        deal(t0, user, 10 ether);
        deal(t1, user, 10 ether);
        deal(t2, user, 10 ether);
        deal(t3, user, 10 ether);
    }

    function setupApproves(address t) internal {
        IERC20(t).approve(address(permit2), type(uint256).max);
        IERC20(t).approve(address(swapRouter), type(uint256).max);

        permit2.approve(t, address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(t, address(poolManager), type(uint160).max, type(uint48).max);
    }

    function setupPool(address token0, address token1) internal {
        currency0 = Currency.wrap(token0);
        currency1 = Currency.wrap(token1);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        try poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1) {
            deal(token0, address(this), 10 ether);
            deal(token1, address(this), 10 ether);

            // Provide full-range liquidity to the pool
            tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
            tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

            uint128 liquidityAmount = 1 ether;

            (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidityAmount
            );
            console.log("l0", amount0Expected);

            (tokenId,) = positionManager.mint(
                poolKey,
                tickLower,
                tickUpper,
                liquidityAmount,
                amount0Expected + 1,
                amount1Expected + 1,
                address(this),
                block.timestamp,
                Constants.ZERO_BYTES
            );
        } catch {
            console.log("Pool already exists");
            return;

            (uint160 sqrtP,,,) = poolManager.getSlot0(poolId);

            // 1) Target price boundary (for a very tight JIT band at current price)
            tickLower = getLowerUsableTick(TickMath.getTickAtSqrtPrice(sqrtP), poolKey.tickSpacing);
            tickLower -= poolKey.tickSpacing;
            tickUpper = tickLower + poolKey.tickSpacing;

            uint128 liquidityAmount = 1 ether;

            (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidityAmount
            );
            console.log("l0", amount0Expected);

            (tokenId,) = positionManager.mint(
                poolKey,
                tickLower,
                tickUpper,
                liquidityAmount,
                amount0Expected + 1,
                amount1Expected + 1,
                address(this),
                block.timestamp,
                Constants.ZERO_BYTES
            );
        }
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

    function testCounterHooks() public {
        //poolKey.currency0.transfer(address(hook.vault()), 5 ether);
        //poolKey.currency1.transfer(address(hook.vault()), 5 ether);

        // positions were created in setup()

        console.log(poolKey.currency0.balanceOf(address(hook.vault())));
        console.log(poolKey.currency1.balanceOf(address(hook.vault())));

        vm.startPrank(user);
        IERC20(Currency.unwrap(poolKey.currency0)).approve(address(swapRouter), type(uint256).max);

        // Perform a test swap //
        uint256 amountIn = 14 ether;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: user,
            deadline: block.timestamp + 1
        });

        console.log("userBalance T0", poolKey.currency0.balanceOf(user));
        console.log("userBalance T1", poolKey.currency1.balanceOf(user));
        vm.stopPrank();
        // ------------------- //

        console.log("Vault T0", poolKey.currency0.balanceOf(address(hook.vault())));
        console.log("Vault T1", poolKey.currency1.balanceOf(address(hook.vault())));
        console.log("Hook T0", poolKey.currency0.balanceOf(address(hook)));
        console.log("Hook T1", poolKey.currency1.balanceOf(address(hook)));

        assertEq(int256(swapDelta.amount0()), -int256(amountIn));
    }

    function testCounterHooks2() public {
        poolKey.currency0.transfer(user, 14 ether);

        // positions were created in setup()

        vm.startPrank(user);
        IERC20(Currency.unwrap(poolKey.currency0)).approve(address(swapRouter), type(uint256).max);

        // Perform a test swap //
        uint256 amountIn = 14 ether;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: user,
            deadline: block.timestamp + 1
        });

        console.log("userBalance T0", poolKey.currency0.balanceOf(user));
        console.log("userBalance T1", poolKey.currency1.balanceOf(user));
        vm.stopPrank();
        // ------------------- //

        console.log("Vault T0", poolKey.currency0.balanceOf(address(hook.vault())));
        console.log("Vault T1", poolKey.currency1.balanceOf(address(hook.vault())));

        assertEq(int256(swapDelta.amount0()), -int256(amountIn));
    }

    function testLiquidityHooks() public {
        // remove liquidity
        uint256 liquidityToRemove = 1e18;
        positionManager.decreaseLiquidity(
            tokenId,
            liquidityToRemove,
            0, // Max slippage, token0
            0, // Max slippage, token1
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }
}
