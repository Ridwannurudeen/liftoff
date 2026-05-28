// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BaseTest} from "./utils/BaseTest.sol";
import {SealedLaunchHook} from "../src/SealedLaunchHook.sol";
import {SealedLaunch} from "../src/SealedLaunch.sol";

contract SealedLaunchTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    SealedLaunchHook hook;
    SealedLaunch launch;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapTest;
    MockERC20 quote;

    address token;
    PoolKey key;
    PoolId id;
    bool tokenIsC0;

    uint64 START;
    uint64 END;

    uint256 constant TOTAL_SUPPLY = 1_000_000 ether;
    uint256 constant OFFERED = 400_000 ether;
    uint256 constant LP_TOKENS = 300_000 ether;
    int24 constant TICK_SPACING = 60;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address launcher = makeAddr("launcher");

    function setUp() public {
        deployArtifactsAndLabel();
        lpRouter = new PoolModifyLiquidityTest(poolManager);
        swapTest = new PoolSwapTest(poolManager);

        address flags = address(
            uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG)
                ^ (0x4444 << 144)
        );
        deployCodeTo("SealedLaunchHook.sol:SealedLaunchHook", abi.encode(poolManager, address(this)), flags);
        hook = SealedLaunchHook(flags);

        launch = new SealedLaunch(poolManager, hook);
        hook.setManagerAllowed(address(launch), true);

        quote = new MockERC20("Quote", "Q", 18);
        quote.mint(address(this), 1_000_000 ether); // for post-settlement trading from the test contract

        START = uint64(block.timestamp);
        END = uint64(block.timestamp + 1 hours);

        vm.prank(launcher);
        (token, key, id) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "Sealed",
                symbol: "SEAL",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                endTime: END,
                minRaise: 0,
                maxCommitPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );
        tokenIsC0 = Currency.unwrap(key.currency0) == token;

        _fund(alice, 1_000_000 ether);
        _fund(bob, 1_000_000 ether);
        _fund(carol, 1_000_000 ether);

        // approvals for the post-settlement trading routers
        IERC20(address(quote)).approve(address(swapTest), type(uint256).max);
        IERC20(address(quote)).approve(address(lpRouter), type(uint256).max);
    }

    function _fund(address user, uint256 amount) internal {
        quote.mint(user, amount);
        vm.prank(user);
        IERC20(address(quote)).approve(address(launch), type(uint256).max);
    }

    function _commit(address user, uint256 amount) internal {
        vm.prank(user);
        launch.commit(id, amount);
    }

    // --- swaps blocked pre-settlement -------------------------------------

    function test_swapBlockedBeforeSettle() public {
        // Cannot even swap because the pool is not initialized until settle; but even a configured/
        // initialized pool would revert via beforeSwap. Drive the auction to a settled pool and prove
        // the gate flips: before settle, swap reverts; after settle, swap succeeds.
        _commit(alice, 100 ether);
        vm.warp(END + 1);

        // Before settle: pool not initialized + hook gate. A swap attempt reverts.
        vm.expectRevert();
        _swapBuyToken(1 ether);

        launch.settle(id);
        assertTrue(hook.isSettled(id));

        // After settle: swapping succeeds (need the token side too; quote->token buy works against LP).
        _swapBuyToken(1 ether);
    }

    function test_isSettledFlipsOnSettle() public {
        assertFalse(hook.isSettled(id));
        _commit(alice, 50 ether);
        vm.warp(END + 1);
        launch.settle(id);
        assertTrue(hook.isSettled(id));
    }

    /// @dev Direct unit test of the hook gate: beforeSwap reverts with the explicit error pre-settlement,
    /// independent of pool-initialization order. The pool manager is the only allowed caller.
    function test_beforeSwapGateRevertsExplicitly() public {
        SwapParams memory sp =
            SwapParams({zeroForOne: true, amountSpecified: -1, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});
        vm.prank(address(poolManager));
        vm.expectRevert(SealedLaunchHook.SwapsLockedUntilSettled.selector);
        hook.beforeSwap(address(this), key, sp, "");
    }

    /// @dev Direct unit test of the LP gate: a non-manager add-liquidity reverts with the explicit error.
    function test_beforeAddLiquidityGateRevertsForNonManager() public {
        ModifyLiquidityParams memory mp = ModifyLiquidityParams({
            tickLower: TickMath.minUsableTick(TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(TICK_SPACING),
            liquidityDelta: int256(1e18),
            salt: bytes32(0)
        });
        vm.prank(address(poolManager));
        vm.expectRevert(SealedLaunchHook.AddLiquidityLockedUntilSettled.selector);
        hook.beforeAddLiquidity(address(this), key, mp, ""); // sender = test contract, not the manager
    }

    // --- LP front-run blocked pre-settlement ------------------------------

    function test_addLiquidityBlockedForNonManagerPreSettle() public {
        // The pool isn't initialized pre-settle, so an outsider add-liquidity must revert (gate + uninit).
        vm.expectRevert();
        lpRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(TICK_SPACING),
                tickUpper: TickMath.maxUsableTick(TICK_SPACING),
                liquidityDelta: int256(1e18),
                salt: bytes32(0)
            }),
            Constants.ZERO_BYTES
        );
    }

    function test_addLiquidityAllowedAfterSettle() public {
        _commit(alice, 100 ether);
        vm.warp(END + 1);
        launch.settle(id);

        // After settlement the gate is open: an outsider can add liquidity. Acquire some token first via a
        // real swap so this contract holds both currencies for a full-range position.
        _swapBuyToken(10 ether);
        IERC20(token).approve(address(lpRouter), type(uint256).max);

        lpRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(TICK_SPACING),
                tickUpper: TickMath.maxUsableTick(TICK_SPACING),
                liquidityDelta: int256(1e15),
                salt: bytes32(0)
            }),
            Constants.ZERO_BYTES
        );
    }

    // --- uniform price / order independence -------------------------------

    function test_equalCommitsEqualAllocations_regardlessOfOrder() public {
        // alice commits first, bob second; carol commits the same total but split across the window.
        _commit(alice, 100 ether);
        vm.warp(START + 10 minutes);
        _commit(bob, 100 ether);
        vm.warp(START + 20 minutes);
        _commit(carol, 60 ether);
        vm.warp(START + 40 minutes);
        _commit(carol, 40 ether); // carol total 100, like alice & bob

        vm.warp(END + 1);
        launch.settle(id);

        uint256 aAlloc = launch.allocationOf(id, alice);
        uint256 bAlloc = launch.allocationOf(id, bob);
        uint256 cAlloc = launch.allocationOf(id, carol);
        assertEq(aAlloc, bAlloc, "equal commit -> equal alloc regardless of order");
        assertEq(aAlloc, cAlloc, "splitting commits across blocks changes nothing");
    }

    function test_sniperFirstBlockSamePricePerTokenAsLastBlock() public {
        // "sniper" commits in the very first block; "laggard" commits an equal amount in the last block.
        address sniper = alice;
        address laggard = bob;

        _commit(sniper, 250 ether); // first block (block.timestamp == START)
        vm.warp(END); // last block in window
        _commit(laggard, 250 ether);

        vm.warp(END + 1);
        launch.settle(id);

        uint256 sniperAlloc = launch.allocationOf(id, sniper);
        uint256 laggardAlloc = launch.allocationOf(id, laggard);
        assertEq(sniperAlloc, laggardAlloc, "first-block and last-block buyer get identical allocations");

        // Per-token price is identical by construction: price = totalCommitted/offered, single uniform value.
        // Verify each paid the same quote per token: committed/alloc equal for both.
        // (commit equal, alloc equal => price-per-token equal.)
        assertEq(
            FullMath.mulDiv(250 ether, 1e18, sniperAlloc),
            FullMath.mulDiv(250 ether, 1e18, laggardAlloc),
            "uniform price per token"
        );
    }

    function test_proRataAllocation_unequalCommits() public {
        _commit(alice, 300 ether); // 60%
        _commit(bob, 200 ether); // 40%
        vm.warp(END + 1);
        launch.settle(id);

        assertEq(launch.allocationOf(id, alice), FullMath.mulDiv(OFFERED, 300 ether, 500 ether));
        assertEq(launch.allocationOf(id, bob), FullMath.mulDiv(OFFERED, 200 ether, 500 ether));
        // total offered conserved (within flooring dust)
        assertLe(launch.allocationOf(id, alice) + launch.allocationOf(id, bob), OFFERED);
    }

    // --- claim ------------------------------------------------------------

    function test_claimTransfersAllocation() public {
        _commit(alice, 300 ether);
        _commit(bob, 100 ether);
        vm.warp(END + 1);
        launch.settle(id);

        uint256 aExpected = launch.allocationOf(id, alice);
        vm.prank(alice);
        launch.claim(id);
        assertEq(IERC20(token).balanceOf(alice), aExpected);

        // double claim reverts
        vm.prank(alice);
        vm.expectRevert(SealedLaunch.AlreadyClaimed.selector);
        launch.claim(id);
    }

    function test_claimRevertsBeforeSettle() public {
        _commit(alice, 100 ether);
        vm.prank(alice);
        vm.expectRevert(SealedLaunch.NotSettled.selector);
        launch.claim(id);
    }

    // --- failed launch / refunds ------------------------------------------

    function test_failedLaunch_refunds_noPoolSeeded() public {
        // Fresh launch with a minRaise that won't be met.
        (,, PoolId id2) = _newLaunch(500 ether, TICK_SPACING);

        vm.prank(alice);
        launch.commit(id2, 100 ether); // below minRaise

        uint256 balBefore = quote.balanceOf(alice);
        vm.warp(END + 1);
        launch.settle(id2);

        SealedLaunch.Launch memory l = launch.getLaunch(id2);
        assertTrue(l.settled);
        assertTrue(l.failed);
        assertEq(l.clearingSqrtPriceX96, 0, "no clearing price set on failure");

        // pool was never initialized
        (uint160 sp,,,) = poolManager.getSlot0(id2);
        assertEq(sp, 0, "pool not initialized on failed launch");

        // refund returns the exact commitment
        vm.prank(alice);
        launch.refund(id2);
        assertEq(quote.balanceOf(alice), balBefore + 100 ether);

        // second refund reverts (nothing to refund)
        vm.prank(alice);
        vm.expectRevert(SealedLaunch.NothingToRefund.selector);
        launch.refund(id2);

        // claim not possible on failed launch
        vm.prank(alice);
        vm.expectRevert(SealedLaunch.LaunchFailed.selector);
        launch.claim(id2);
    }

    function test_refundRevertsWhenSucceeded() public {
        _commit(alice, 100 ether);
        vm.warp(END + 1);
        launch.settle(id);
        vm.prank(alice);
        vm.expectRevert(SealedLaunch.LaunchSucceeded.selector);
        launch.refund(id);
    }

    // --- pool opens at clearing price -------------------------------------

    function test_poolInitializedAtClearingPrice() public {
        // P = totalCommitted / offered. Commit so P is a clean ratio.
        _commit(alice, OFFERED / 1e18 * 2 ether); // totalCommitted = offered*2 (in 1e18 units) => P = 2
        vm.warp(END + 1);
        launch.settle(id);

        uint160 expected = launch.clearingPrice(id);
        (uint160 actual,,,) = poolManager.getSlot0(id);
        assertEq(actual, expected, "slot0 price equals stored clearing price");
        assertGt(actual, 0);

        // Cross-check the price magnitude: price (currency1/currency0) should reflect quote-per-token P=2
        // when token is currency0, or 1/2 when token is currency1.
        uint256 priceX96sq = uint256(actual) * uint256(actual); // = price * 2^192
        uint256 priceQ96 = priceX96sq >> 96; // price * 2^96 (approx)
        if (tokenIsC0) {
            // price ~ 2 -> priceQ96 ~ 2 * 2^96
            assertApproxEqRel(priceQ96, 2 * (1 << 96), 1e15); // within 0.1%
        } else {
            assertApproxEqRel(priceQ96, (1 << 96) / 2, 1e15);
        }
    }

    function test_settleSeedsLiquidityAndOpensTrading() public {
        _commit(alice, 200 ether);
        _commit(bob, 200 ether);
        vm.warp(END + 1);
        launch.settle(id);

        // pool has liquidity now
        uint128 liq = poolManager.getLiquidity(id);
        assertGt(liq, 0, "LP seeded");

        // trading works post-settle
        uint256 tokenBefore = IERC20(token).balanceOf(address(this));
        _swapBuyToken(5 ether);
        assertGt(IERC20(token).balanceOf(address(this)), tokenBefore, "received token from a real swap");
    }

    function test_leftoverQuoteGoesToLauncher() public {
        _commit(alice, 200 ether);
        _commit(bob, 200 ether);
        uint256 launcherBefore = quote.balanceOf(launcher);
        vm.warp(END + 1);
        launch.settle(id);
        // Some raised quote is consumed by LP; the rest goes to the launcher (must be > 0 here).
        assertGt(quote.balanceOf(launcher), launcherBefore, "launcher received leftover quote");
        // SealedLaunch should hold no quote after settlement.
        assertEq(quote.balanceOf(address(launch)), 0, "no quote stranded in SealedLaunch");
    }

    // --- commit guards ----------------------------------------------------

    function test_commit_walletCap() public {
        (, , PoolId id3) = _newLaunchCapped(150 ether, TICK_SPACING);
        vm.prank(alice);
        launch.commit(id3, 100 ether);
        vm.prank(alice);
        vm.expectRevert(SealedLaunch.WalletCapExceeded.selector);
        launch.commit(id3, 60 ether); // would exceed 150 cap
    }

    function test_commit_outsideWindowReverts() public {
        vm.warp(END + 1);
        vm.prank(alice);
        vm.expectRevert(SealedLaunch.NotInWindow.selector);
        launch.commit(id, 1 ether);
    }

    function test_settle_beforeWindowCloseReverts() public {
        _commit(alice, 100 ether);
        vm.expectRevert(SealedLaunch.WindowNotClosed.selector);
        launch.settle(id);
    }

    function test_settle_twiceReverts() public {
        _commit(alice, 100 ether);
        vm.warp(END + 1);
        launch.settle(id);
        vm.expectRevert(SealedLaunch.AlreadySettled.selector);
        launch.settle(id);
    }

    // --- hook config guards -----------------------------------------------

    function test_configureOnlyOnce() public {
        // createLaunch already configured `key`; a direct re-configure by the manager reverts.
        vm.prank(address(launch));
        vm.expectRevert(SealedLaunchHook.AlreadyConfigured.selector);
        hook.configure(key, START, END, address(launch));
    }

    function test_markSettledOnlyManager() public {
        vm.expectRevert(SealedLaunchHook.NotManager.selector);
        hook.markSettled(id);
    }

    function test_initializeRequiresConfigured() public {
        PoolKey memory unconfigured =
            PoolKey(key.currency0, key.currency1, 3000, 120, IHooks(address(hook)));
        vm.expectRevert();
        poolManager.initialize(unconfigured, Constants.SQRT_PRICE_1_1);
    }

    // --- helpers ----------------------------------------------------------

    /// @dev Buy the launch token with `amtIn` of quote via PoolSwapTest. Token is the OTHER side of quote.
    function _swapBuyToken(uint256 amtIn) internal {
        bool zeroForOne = tokenIsC0 ? false : true; // quote -> token
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

    function _newLaunch(uint256 minRaise, int24 spacing)
        internal
        returns (address tok, PoolKey memory k, PoolId i)
    {
        vm.prank(launcher);
        (tok, k, i) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "Sealed2",
                symbol: "SEAL2",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                endTime: END,
                minRaise: minRaise,
                maxCommitPerWallet: 0,
                tickSpacing: spacing
            })
        );
    }

    function _newLaunchCapped(uint256 cap, int24 spacing)
        internal
        returns (address tok, PoolKey memory k, PoolId i)
    {
        vm.prank(launcher);
        (tok, k, i) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "Sealed3",
                symbol: "SEAL3",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                endTime: END,
                minRaise: 0,
                maxCommitPerWallet: cap,
                tickSpacing: spacing
            })
        );
    }

    // ============================================================
    // v1.1 hardening — fixes #1, #3, #4, #9
    // ============================================================

    address launcherA = makeAddr("launcherA");
    address launcherB = makeAddr("launcherB");

    /// @dev Finding #1: pre-v1.1 settle swept `quote.balanceOf(this)` and paid it to the launcher of the
    /// settling launch. With two launches sharing the same quote/manager, settling launch B would drain the
    /// raised escrow of (still-open) launch A and ship it to launcher_B. The fix uses `_quoteUsed` from the
    /// unlock callback so the launcher gets exactly `totalCommitted - quoteUsed`.
    function test_v11_settle_doesNotDrainOtherLaunchEscrow() public {
        // Launch A: window in progress, committed but NOT yet settled. Use a different end time.
        uint64 startA = START;
        uint64 endA = uint64(START + 3 hours); // open longer than B's window
        vm.prank(launcherA);
        (, , PoolId idA) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "LaunchA",
                symbol: "LA",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: startA,
                endTime: endA,
                minRaise: 0,
                maxCommitPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );

        // Launch B: separate token, same quote, shorter window so it settles first.
        uint64 startB = START;
        uint64 endB = END;
        vm.prank(launcherB);
        (, , PoolId idB) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "LaunchB",
                symbol: "LB",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: startB,
                endTime: endB,
                minRaise: 0,
                maxCommitPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );

        // Alice commits to A; Bob commits to B.
        uint256 aliceCommit = 600 ether;
        uint256 bobCommit = 100 ether;
        vm.prank(alice);
        launch.commit(idA, aliceCommit);
        vm.prank(bob);
        launch.commit(idB, bobCommit);

        // Sanity: the manager holds both escrows.
        assertEq(quote.balanceOf(address(launch)), aliceCommit + bobCommit, "manager holds both escrows");

        uint256 launcherBBefore = quote.balanceOf(launcherB);

        // Close + settle B while A is still open. With the bug, settle would pay launcherB the FULL contract
        // balance minus LP usage — which includes Alice's 600 still-escrowed quote.
        vm.warp(endB + 1);
        launch.settle(idB);

        // Launcher B can only have received up to their own raise (minus LP usage). Strictly < aliceCommit.
        uint256 launcherBGained = quote.balanceOf(launcherB) - launcherBBefore;
        assertLe(launcherBGained, bobCommit, "launcher B paid no more than launch B's raise");

        // The manager must still hold AT LEAST Alice's full commitment so launch A is solvent.
        assertGe(quote.balanceOf(address(launch)), aliceCommit, "launch A escrow preserved");

        // And the still-open launch A must remain settleable: Alice can ultimately claim her allocation.
        vm.warp(endA + 1);
        launch.settle(idA);
        vm.prank(alice);
        launch.claim(idA);
        assertGt(IERC20(launch.getLaunch(idA).token).balanceOf(alice), 0, "Alice still gets her allocation");
    }

    /// @dev Finding #3: pre-v1.1, if `_sqrtPriceX96` produced a value outside TickMath bounds (extreme ratio
    /// of offeredTokens to totalCommitted), `poolManager.initialize` would revert and settle would brick —
    /// committers permanently locked out of refund. The fix marks the launch failed and unlocks refund.
    function test_v11_settle_bricksOnBadPriceMarksFailed() public {
        // Brand-new launch with an enormous `offeredTokens` so even a 1-wei commit makes the price ~0.
        vm.prank(launcher);
        (, , PoolId idBad) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "BadPrice",
                symbol: "BAD",
                totalSupply: type(uint128).max,
                offeredTokens: type(uint128).max - 1, // huge denominator => clearing price ~ 0
                lpTokens: 1,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                endTime: END,
                minRaise: 0,
                maxCommitPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );
        vm.prank(alice);
        launch.commit(idBad, 1); // 1 wei commit

        vm.warp(END + 1);
        // Should NOT brick. settle marks the launch failed and emits LaunchFailedEvent.
        launch.settle(idBad);
        SealedLaunch.Launch memory l = launch.getLaunch(idBad);
        assertTrue(l.settled);
        assertTrue(l.failed, "out-of-range clearing price marks the launch failed instead of bricking");

        // And alice can refund — committers are NOT locked.
        uint256 balBefore = quote.balanceOf(alice);
        vm.prank(alice);
        launch.refund(idBad);
        assertEq(quote.balanceOf(alice), balBefore + 1, "refund unlocked after bad-price failure");
    }

    /// @dev Finding #3 (companion): createLaunch must reject tickSpacing=0 up-front (would otherwise cause
    /// division-by-zero inside TickMath.minUsableTick during settle).
    function test_v11_createLaunch_rejectsZeroTickSpacing() public {
        vm.prank(launcher);
        vm.expectRevert(SealedLaunch.BadParams.selector);
        launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "Zero",
                symbol: "ZTS",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                endTime: END,
                minRaise: 0,
                maxCommitPerWallet: 0,
                tickSpacing: 0
            })
        );
    }

    /// @dev Finding #4: a malicious ERC-777-style quote token that hooks `transferFrom` and reenters
    /// `commit` would, pre-v1.1, double-credit the attacker (inflate `totalCommitted`/`committed` past
    /// the funds actually delivered). With `nonReentrant`, the reentrant call reverts.
    function test_v11_commit_reentrancyBlocked() public {
        ReentrantQuoteToken evil = new ReentrantQuoteToken();
        // Spin up a launch that uses the malicious token as quote.
        vm.prank(launcher);
        (, , PoolId idEvil) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "Evil",
                symbol: "EV",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(evil)),
                startTime: START,
                endTime: END,
                minRaise: 0,
                maxCommitPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );

        // Configure the token to reenter `commit` during transferFrom.
        evil.mint(alice, 100 ether);
        vm.prank(alice);
        evil.approve(address(launch), type(uint256).max);
        evil.arm(address(launch), idEvil, 10 ether);

        // The reentrant call to `commit` inside transferFrom must revert (ReentrancyGuardReentrantCall),
        // which propagates and reverts the outer commit too.
        vm.prank(alice);
        vm.expectRevert();
        launch.commit(idEvil, 10 ether);
    }

    /// @dev Finding #9: configure() can only be called by an allowlisted manager or the hook owner. A
    /// random EOA / contract calling `hook.configure(...)` with itself as the manager is rejected.
    function test_v11_configure_frontRunBlockedByAllowlist() public {
        // Build a fresh PoolKey that's not yet configured.
        PoolKey memory k =
            PoolKey(key.currency0, key.currency1, 3000, int24(120), IHooks(address(hook)));

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SealedLaunchHook.ManagerNotAllowed.selector);
        hook.configure(k, START, END, attacker);
    }
}

// ============================================================================
// Malicious ERC-777-style quote token used by the v1.1 reentrancy test. Hooks
// `transferFrom` to reenter the launch contract — must be blocked by nonReentrant.
// ============================================================================

contract ReentrantQuoteToken {
    string public constant name = "Evil";
    string public constant symbol = "EVL";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    SealedLaunch private _target;
    PoolId private _id;
    uint256 private _amt;
    bool private _armed;
    bool private _entered;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (_armed && !_entered) {
            _entered = true;
            // ERC-777-style reentrancy: try to commit AGAIN before the outer commit finishes.
            _target.commit(_id, _amt);
        }
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function arm(address target, PoolId id, uint256 amt) external {
        _target = SealedLaunch(target);
        _id = id;
        _amt = amt;
        _armed = true;
    }
}
