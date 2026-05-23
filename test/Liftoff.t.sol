// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {Liftoff} from "../src/Liftoff.sol";

contract LiftoffTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0; // launched token
    Currency currency1; // quote

    Liftoff hook;
    PoolKey poolKey;
    PoolId poolId;
    uint256 tokenId;

    uint64 constant WINDOW = 1 hours;
    uint24 constant START_FEE = 500_000; // 50%
    uint24 constant END_FEE = 3_000; // 0.3%
    uint256 constant MAX_BUY = 1e18;
    uint256 constant MAX_SELL = 1e18;
    uint256 constant GRAD_VOLUME = 5e18;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x5555 << 144)
        );
        deployCodeTo("Liftoff.sol:Liftoff", abi.encode(poolManager), flags);
        hook = Liftoff(flags);

        // Dynamic-fee pool so the hook can override the fee per swap.
        poolKey = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = poolKey.toId();

        hook.configureLaunch(
            poolKey,
            Liftoff.LaunchConfig({
                tokenIsCurrency0: true,
                startFee: START_FEE,
                endFee: END_FEE,
                baselineFee: END_FEE,
                launchWindow: WINDOW,
                maxBuyPerTx: MAX_BUY,
                graduationVolume: GRAD_VOLUME,
                lpLockUntil: uint64(block.timestamp + 1 days),
                maxSellPerTx: MAX_SELL
            })
        );

        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);
        uint128 liquidity = 100e18;
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        (tokenId,) = positionManager.mint(
            poolKey, tickLower, tickUpper, liquidity, a0 + 1, a1 + 1, address(this), block.timestamp, Constants.ZERO_BYTES
        );
    }

    function _buy(uint256 amountIn) internal {
        // buying currency0 (the token) means swapping currency1 -> currency0, i.e. zeroForOne = false
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: false,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function _sell(uint256 amountIn) internal {
        // selling currency0 (the token) -> currency1, i.e. zeroForOne = true
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function _graduated() internal view returns (bool g) {
        (, g,,,) = hook.states(poolId);
    }

    function test_antiSnipeFeeDecays() public {
        assertEq(hook.currentBuyFee(poolId), START_FEE); // elapsed 0
        vm.warp(block.timestamp + WINDOW / 2);
        uint24 mid = hook.currentBuyFee(poolId);
        assertLt(mid, START_FEE);
        assertGt(mid, END_FEE);
        vm.warp(block.timestamp + WINDOW); // past window
        assertEq(hook.currentBuyFee(poolId), END_FEE);
    }

    function test_buyCapReverts() public {
        vm.expectRevert();
        _buy(MAX_BUY + 1);
    }

    function test_buyWithinCapSucceeds() public {
        _buy(MAX_BUY); // exactly at cap, must not revert
        (,,,, uint256 vol) = hook.states(poolId);
        assertGt(vol, 0);
    }

    function test_graduation_byTime_flipsToBaseline() public {
        assertFalse(_graduated());
        vm.warp(block.timestamp + WINDOW + 1);
        _buy(MAX_BUY); // afterSwap sees window elapsed -> graduate
        assertTrue(_graduated());
        assertEq(hook.currentBuyFee(poolId), END_FEE);
    }

    function test_graduation_byVolume() public {
        for (uint256 i = 0; i < 5; i++) {
            _buy(MAX_BUY); // 5 x 1e18 quote volume == GRAD_VOLUME
        }
        assertTrue(_graduated());
    }

    function decreaseExternal(uint256 liq) external {
        positionManager.decreaseLiquidity(tokenId, liq, 0, 0, address(this), block.timestamp, Constants.ZERO_BYTES);
    }

    function test_lpLocked_thenUnlocks() public {
        vm.expectRevert(); // before lpLockUntil — single external call boundary
        this.decreaseExternal(1e18);

        vm.warp(block.timestamp + 2 days); // past lpLockUntil
        positionManager.decreaseLiquidity(tokenId, 1e18, 0, 0, address(this), block.timestamp, Constants.ZERO_BYTES);
    }

    function test_antiDump_sellCapAfterGraduation() public {
        vm.warp(block.timestamp + WINDOW + 1);
        _buy(MAX_BUY); // graduate
        assertTrue(_graduated());

        _sell(MAX_SELL); // within cap: ok
        vm.expectRevert();
        _sell(MAX_SELL + 1); // exceeds cap: revert
    }

    function test_configure_nonDynamicFeeReverts() public {
        PoolKey memory staticKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        vm.expectRevert(Liftoff.NotDynamicFee.selector);
        hook.configureLaunch(staticKey, _defaultCfg());
    }

    function test_configure_doubleReverts() public {
        vm.expectRevert(Liftoff.AlreadyConfigured.selector);
        hook.configureLaunch(poolKey, _defaultCfg());
    }

    function test_initialize_requiresConfig() public {
        // a different pool (new tickSpacing) that was never configured
        PoolKey memory unconfigured = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 120, IHooks(hook));
        vm.expectRevert();
        poolManager.initialize(unconfigured, Constants.SQRT_PRICE_1_1);
    }

    function _defaultCfg() internal view returns (Liftoff.LaunchConfig memory) {
        return Liftoff.LaunchConfig({
            tokenIsCurrency0: true,
            startFee: START_FEE,
            endFee: END_FEE,
            baselineFee: END_FEE,
            launchWindow: WINDOW,
            maxBuyPerTx: MAX_BUY,
            graduationVolume: GRAD_VOLUME,
            lpLockUntil: uint64(block.timestamp + 1 days),
            maxSellPerTx: MAX_SELL
        });
    }
}
