// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
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
import {LiftoffRouter} from "../src/LiftoffRouter.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract LiftoffTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0; // launched token
    Currency currency1; // quote

    Liftoff hook;
    LiftoffRouter liftoffRouter;
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
        liftoffRouter = new LiftoffRouter(poolManager);
        deployCodeTo("Liftoff.sol:Liftoff", abi.encode(poolManager, address(liftoffRouter)), flags);
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
                maxBuyPerWallet: 0,
                graduationVolume: GRAD_VOLUME,
                lpLockUntil: uint64(block.timestamp + 1 days),
                maxSellPerTx: MAX_SELL,
                maxSellPerWallet: 0,
                maxSellBpsOfReserve: 0
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
            maxBuyPerWallet: 0,
            graduationVolume: GRAD_VOLUME,
            lpLockUntil: uint64(block.timestamp + 1 days),
            maxSellPerTx: MAX_SELL,
            maxSellPerWallet: 0,
            maxSellBpsOfReserve: 0
        });
    }

    // --- Phase 2: helpers --------------------------------------------------

    function _newPool(int24 spacing, Liftoff.LaunchConfig memory cfg)
        internal
        returns (PoolKey memory key, PoolId id)
    {
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, spacing, IHooks(hook));
        id = key.toId();
        hook.configureLaunch(key, cfg);
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);

        int24 tl = TickMath.minUsableTick(spacing);
        int24 tu = TickMath.maxUsableTick(spacing);
        uint128 liq = 100e18;
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1, TickMath.getSqrtPriceAtTick(tl), TickMath.getSqrtPriceAtTick(tu), liq
        );
        positionManager.mint(key, tl, tu, liq, a0 + 1, a1 + 1, address(this), block.timestamp, Constants.ZERO_BYTES);
    }

    function _fundApprove(address user) internal {
        MockERC20(Currency.unwrap(currency0)).mint(user, 1_000_000 ether);
        MockERC20(Currency.unwrap(currency1)).mint(user, 1_000_000 ether);
        vm.startPrank(user);
        MockERC20(Currency.unwrap(currency0)).approve(address(liftoffRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(liftoffRouter), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Buy currency0 (token) via the trusted router. amountSpecified < 0 = exact input (quote in),
    /// > 0 = exact output (token out).
    function _routerBuy(address user, PoolKey memory key, int256 amountSpecified) internal {
        vm.prank(user);
        liftoffRouter.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: amountSpecified, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1})
        );
    }

    function _buyOn(PoolKey memory key, uint256 amtIn) internal {
        swapRouter.swapExactTokensForTokens({
            amountIn: amtIn,
            amountOutMin: 0,
            zeroForOne: false,
            poolKey: key,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    function _sellOn(PoolKey memory key, uint256 amtIn) internal {
        swapRouter.swapExactTokensForTokens({
            amountIn: amtIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: key,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }

    // --- Phase 2: per-wallet caps (item A) ---------------------------------

    function test_perWalletBuyCap_viaTrustedRouter() public {
        Liftoff.LaunchConfig memory cfg = _defaultCfg();
        cfg.maxBuyPerTx = 0; // isolate the per-wallet cap
        cfg.maxBuyPerWallet = 1e18;
        cfg.graduationVolume = 1_000e18; // stay pre-graduation
        (PoolKey memory key, PoolId id) = _newPool(120, cfg);

        address alice = makeAddr("alice");
        _fundApprove(alice);

        _routerBuy(alice, key, -6e17); // spend 0.6 quote
        _routerBuy(alice, key, -4e17); // cumulative 1.0 == cap, ok
        assertEq(hook.boughtBy(id, alice), 1e18);

        vm.expectRevert();
        _routerBuy(alice, key, -1e16); // would exceed the per-wallet cap
    }

    function test_perWalletBuyCap_isolatedAcrossUsers() public {
        Liftoff.LaunchConfig memory cfg = _defaultCfg();
        cfg.maxBuyPerTx = 0;
        cfg.maxBuyPerWallet = 1e18;
        cfg.graduationVolume = 1_000e18;
        (PoolKey memory key, PoolId id) = _newPool(240, cfg);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        _fundApprove(alice);
        _fundApprove(bob);

        _routerBuy(alice, key, -1e18); // alice at cap
        vm.expectRevert();
        _routerBuy(alice, key, -1e16); // alice over cap

        _routerBuy(bob, key, -1e18); // bob is independent
        assertEq(hook.boughtBy(id, bob), 1e18);
    }

    function test_perWalletCap_txOriginFallback() public {
        Liftoff.LaunchConfig memory cfg = _defaultCfg();
        cfg.maxBuyPerTx = 0;
        cfg.maxBuyPerWallet = 1e18;
        cfg.graduationVolume = 1_000e18;
        (PoolKey memory key, PoolId id) = _newPool(180, cfg);

        // An UNTRUSTED router: the hook can't trust its hookData, so it keys caps on tx.origin.
        LiftoffRouter untrusted = new LiftoffRouter(poolManager);
        address alice = makeAddr("alice");
        MockERC20(Currency.unwrap(currency1)).mint(alice, 1_000_000 ether);
        vm.prank(alice);
        MockERC20(Currency.unwrap(currency1)).approve(address(untrusted), type(uint256).max);

        vm.prank(alice, alice); // sets msg.sender AND tx.origin = alice
        untrusted.swap(
            key, SwapParams({zeroForOne: false, amountSpecified: -5e17, sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1})
        );

        assertEq(hook.boughtBy(id, alice), 5e17); // accounted to tx.origin
    }

    // --- Phase 2: % of reserve sell cap (item C) ---------------------------

    function test_sellReserveCap_percentOfReserve() public {
        Liftoff.LaunchConfig memory cfg = _defaultCfg();
        cfg.maxSellPerTx = 0;
        cfg.maxSellBpsOfReserve = 1000; // 10%
        cfg.graduationVolume = 1; // graduate on the first swap
        (PoolKey memory key, PoolId id) = _newPool(300, cfg);

        _buyOn(key, 1e15); // graduate
        (, bool g,,,) = hook.states(id);
        assertTrue(g);

        // Full-range reserve ~100e18 at price 1; 10% ~10e18.
        _sellOn(key, 5e18); // under 10%: ok
        vm.expectRevert();
        _sellOn(key, 50e18); // over 10%: revert
    }

    // --- Phase 2: exact-output handling (item D) ---------------------------

    function test_exactOutputBuy_capsOnQuoteSpent() public {
        Liftoff.LaunchConfig memory cfg = _defaultCfg();
        cfg.startFee = 3000; // flat low fee so quote spent ~ token out
        cfg.endFee = 3000;
        cfg.baselineFee = 3000;
        cfg.maxBuyPerTx = 1e18; // cap is in quote-in units
        cfg.graduationVolume = 1_000e18;
        (PoolKey memory key,) = _newPool(360, cfg);

        address alice = makeAddr("alice");
        _fundApprove(alice);

        _routerBuy(alice, key, int256(5e17)); // exact-output: ~0.5 quote spent < cap, ok
        vm.expectRevert();
        _routerBuy(alice, key, int256(2e18)); // exact-output: ~2 quote spent > cap, revert
    }
}
