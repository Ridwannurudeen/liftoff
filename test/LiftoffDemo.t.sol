// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BaseTest} from "./utils/BaseTest.sol";
import {Liftoff} from "../src/Liftoff.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";

/// @notice A narrated end-to-end launch story. Run with:
///   forge test --match-test test_demo_fullLifecycle -vv
/// to print each stage — a ready-made script for the demo video.
contract LiftoffDemoTest is BaseTest {
    using PoolIdLibrary for PoolKey;

    Liftoff hook;
    LaunchFactory factory;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapTest;
    MockERC20 quote;

    address token;
    PoolKey key;
    PoolId id;
    bool tokenIsC0;

    function setUp() public {
        deployArtifactsAndLabel();
        lpRouter = new PoolModifyLiquidityTest(poolManager);
        swapTest = new PoolSwapTest(poolManager);

        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x8888 << 144)
        );
        deployCodeTo("Liftoff.sol:Liftoff", abi.encode(poolManager), flags);
        hook = Liftoff(flags);
        factory = new LaunchFactory(poolManager, hook);

        quote = new MockERC20("Quote", "Q", 18);
        quote.mint(address(this), 1e30);

        (token, key, id) = factory.launch(
            LaunchFactory.LaunchParams({
                name: "DemoCoin",
                symbol: "DEMO",
                supply: 1e27,
                quote: Currency.wrap(address(quote)),
                sqrtPriceX96: Constants.SQRT_PRICE_1_1,
                startFee: 800_000, // 80% anti-snipe
                endFee: 3_000, // 0.3%
                baselineFee: 3_000,
                launchWindow: 1 hours,
                maxBuyPerTx: 1e18,
                graduationVolume: 3e18,
                lpLockUntil: uint64(block.timestamp + 30 days),
                maxSellPerTx: 5e17
            })
        );
        tokenIsC0 = Currency.unwrap(key.currency0) == token;

        IERC20(token).approve(address(lpRouter), type(uint256).max);
        IERC20(address(quote)).approve(address(lpRouter), type(uint256).max);
        IERC20(token).approve(address(swapTest), type(uint256).max);
        IERC20(address(quote)).approve(address(swapTest), type(uint256).max);

        lpRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: int256(1e21),
                salt: bytes32(0)
            }),
            Constants.ZERO_BYTES
        );
    }

    function buyExt(uint256 a) external {
        _buy(a);
    }

    function sellExt(uint256 a) external {
        _sell(a);
    }

    function _buy(uint256 amtIn) internal {
        bool zeroForOne = !tokenIsC0;
        swapTest.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amtIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            Constants.ZERO_BYTES
        );
    }

    function _sell(uint256 amtIn) internal {
        bool zeroForOne = tokenIsC0;
        swapTest.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amtIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            Constants.ZERO_BYTES
        );
    }

    function _graduated() internal view returns (bool g) {
        (, g,,,) = hook.states(id);
    }

    function test_demo_fullLifecycle() public {
        console.log("=== LIFTOFF: fair launch + fair life ===");
        console.log("Launch fee at T+0 (pips):", uint256(hook.currentBuyFee(id)));

        console.log("-- Sniper bot tries to buy 5e18 (cap is 1e18) --");
        try this.buyExt(5e18) {
            console.log("   sniper went through (unexpected)");
        } catch {
            console.log("   BLOCKED: per-tx buy cap stopped the snipe");
        }

        console.log("-- Honest buyer buys 1e18 at the (high) launch fee --");
        _buy(1e18);

        vm.warp(block.timestamp + 30 minutes);
        console.log("After 30 min, launch fee decayed to (pips):", uint256(hook.currentBuyFee(id)));

        console.log("-- More honest volume comes in; pool graduates --");
        for (uint256 i = 0; i < 5 && !_graduated(); i++) {
            _buy(1e18);
        }
        require(_graduated(), "demo: expected graduation");
        (,,,, uint256 vol) = hook.states(id);
        console.log("   GRADUATED. cumulative volume:", vol);
        console.log("   fee now baseline (pips):", uint256(hook.currentBuyFee(id)));

        console.log("-- Whale tries to dump 5e18 (sell cap is 5e17) --");
        try this.sellExt(5e18) {
            console.log("   dump went through (unexpected)");
        } catch {
            console.log("   BLOCKED: anti-dump sell cap stopped the cliff dump");
        }

        console.log("-- Normal sell of 3e17 succeeds --");
        _sell(3e17);
        console.log("=== demo complete ===");

        assertTrue(_graduated());
    }
}
