// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Liftoff} from "../src/Liftoff.sol";

/// @notice Forked test against the OFFICIAL Uniswap v4 PoolManager on X Layer mainnet.
/// Run: forge test --match-contract LiftoffForkTest --fork-url https://rpc.xlayer.tech -vv
/// (Skips itself gracefully if no fork RPC is configured.)
contract LiftoffForkTest is Test {
    using PoolIdLibrary for PoolKey;

    address constant XLAYER_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    IPoolManager pm;
    PoolModifyLiquidityTest modifyRouter;
    PoolSwapTest swapRouter;
    Liftoff hook;
    PoolKey key;
    PoolId poolId;
    Currency c0;
    Currency c1;

    uint64 constant WINDOW = 1 hours;
    uint24 constant START_FEE = 500_000;
    uint24 constant END_FEE = 3_000;

    bool forked;

    function setUp() public {
        try vm.createSelectFork("https://rpc.xlayer.tech") {
            forked = true;
        } catch {
            forked = false;
            return;
        }

        // Sanity: the official PoolManager must have code on X Layer.
        require(XLAYER_POOL_MANAGER.code.length > 0, "no PoolManager code on fork");
        pm = IPoolManager(XLAYER_POOL_MANAGER);

        modifyRouter = new PoolModifyLiquidityTest(pm);
        swapRouter = new PoolSwapTest(pm);

        MockERC20 ta = new MockERC20("TokenA", "TKA", 18);
        MockERC20 tb = new MockERC20("TokenB", "TKB", 18);
        ta.mint(address(this), 1e30);
        tb.mint(address(this), 1e30);
        (address a, address b) = address(ta) < address(tb) ? (address(ta), address(tb)) : (address(tb), address(ta));
        c0 = Currency.wrap(a);
        c1 = Currency.wrap(b);
        MockERC20(a).approve(address(modifyRouter), type(uint256).max);
        MockERC20(b).approve(address(modifyRouter), type(uint256).max);
        MockERC20(a).approve(address(swapRouter), type(uint256).max);
        MockERC20(b).approve(address(swapRouter), type(uint256).max);

        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x6666 << 144)
        );
        deployCodeTo("Liftoff.sol:Liftoff", abi.encode(pm, address(0)), flags);
        hook = Liftoff(flags);

        key = PoolKey(c0, c1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = key.toId();

        hook.configureLaunch(
            key,
            Liftoff.LaunchConfig({
                tokenIsCurrency0: true,
                startFee: START_FEE,
                endFee: END_FEE,
                baselineFee: END_FEE,
                launchWindow: WINDOW,
                maxBuyPerTx: 0, // disable cap for the fork end-to-end run
                maxBuyPerWallet: 0,
                graduationVolume: 1e18,
                lpLockUntil: uint64(block.timestamp + 1 days),
                maxSellPerTx: 0,
                maxSellPerWallet: 0,
                maxSellBpsOfReserve: 0
            })
        );

        // Initialize against the REAL X Layer PoolManager (fires beforeInitialize).
        pm.initialize(key, Constants.SQRT_PRICE_1_1);

        // Add full-range liquidity via the v4-core test router.
        modifyRouter.modifyLiquidity(
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

    function _buy(int256 amountIn) internal {
        // buy token0 -> zeroForOne = false (spend currency1)
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -amountIn, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            Constants.ZERO_BYTES
        );
    }

    function test_fork_liftoffWorksOnXLayer() public {
        if (!forked) return; // no fork RPC -> skip

        // anti-snipe fee live at window open
        assertEq(hook.currentBuyFee(poolId), START_FEE);

        // a real swap against the real PoolManager
        _buy(1e16);
        (,,,, uint256 vol) = hook.states(poolId);
        assertGt(vol, 0);

        // graduation by time on the real chain
        vm.warp(block.timestamp + WINDOW + 1);
        _buy(1e18);
        (, bool graduated,,,) = hook.states(poolId);
        assertTrue(graduated);
        assertEq(hook.currentBuyFee(poolId), END_FEE);
    }
}
