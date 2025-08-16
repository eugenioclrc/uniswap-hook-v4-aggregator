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
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";

import {MasterHook} from "../src/MasterHook.sol";

import {console} from "forge-std/console.sol";

contract MasterHookTest is Test, Deployers {
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
        // Deploys all required artifacts.
        deployArtifacts();

        deployMockTokens();

        

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo("MasterHook.sol:MasterHook", constructorArgs, flags);
        hook = MasterHook(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

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
    }

    function deployMockTokens() internal {

        deployCodeTo("WETH.sol:WETH",hex"",0, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        
       
    }

    function testCounterHooks() public {
        poolKey.currency0.transfer(user, 14 ether);
        poolKey.currency0.transfer(address(hook.vault()), 5 ether);
        poolKey.currency1.transfer(address(hook.vault()), 5 ether);

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
