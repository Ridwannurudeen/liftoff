// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BaseTest} from "./utils/BaseTest.sol";
import {SealedLaunchHook} from "../src/SealedLaunchHook.sol";
import {CommitRevealLaunch} from "../src/CommitRevealLaunch.sol";

contract CommitRevealLaunchTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    SealedLaunchHook hook;
    CommitRevealLaunch launch;
    MockERC20 quote;

    address token;
    PoolKey key;
    PoolId id;
    bool tokenIsC0;

    uint64 START;
    uint64 COMMIT_END;
    uint64 REVEAL_END;

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

        address flags = address(
            uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG)
                ^ (0x5555 << 144)
        );
        deployCodeTo("SealedLaunchHook.sol:SealedLaunchHook", abi.encode(poolManager, address(this)), flags);
        hook = SealedLaunchHook(flags);

        launch = new CommitRevealLaunch(poolManager, hook);
        hook.setManagerAllowed(address(launch), true);
        quote = new MockERC20("Quote", "Q", 18);

        START = uint64(block.timestamp);
        COMMIT_END = uint64(block.timestamp + 1 hours);
        REVEAL_END = uint64(block.timestamp + 2 hours);

        vm.prank(launcher);
        (token, key, id) = launch.createLaunch(
            CommitRevealLaunch.LaunchParams({
                name: "Sealed",
                symbol: "SEAL",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                commitEnd: COMMIT_END,
                revealEnd: REVEAL_END,
                minRaise: 0,
                maxMaskedPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );
        tokenIsC0 = Currency.unwrap(key.currency0) == token;

        _fund(alice);
        _fund(bob);
        _fund(carol);
    }

    function _fund(address user) internal {
        quote.mint(user, 1_000_000 ether);
        vm.prank(user);
        IERC20(address(quote)).approve(address(launch), type(uint256).max);
    }

    function _salt(address user) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("salt", user));
    }

    function _commit(address user, uint256 amount, uint256 masked) internal {
        bytes32 c = launch.commitmentFor(amount, _salt(user), user);
        vm.prank(user);
        launch.commit(id, c, masked);
    }

    function _reveal(address user, uint256 amount) internal {
        vm.prank(user);
        launch.reveal(id, amount, _salt(user));
    }

    // --- sealing: the real bid is not on-chain until reveal -------------------

    function test_commitHidesAmount_untilReveal() public {
        _commit(alice, 100 ether, 1000 ether);
        // On-chain the contract only knows the hash + masked deposit, not the bid.
        CommitRevealLaunch.Bid memory b = launch.getBid(id, alice);
        assertEq(b.masked, 1000 ether);
        assertEq(b.revealed, 0);
        assertFalse(b.didReveal);
        assertEq(launch.totalRevealed(id), 0);

        vm.warp(COMMIT_END + 1);
        uint256 balBefore = quote.balanceOf(alice);
        _reveal(alice, 100 ether);

        b = launch.getBid(id, alice);
        assertTrue(b.didReveal);
        assertEq(b.revealed, 100 ether);
        assertEq(launch.totalRevealed(id), 100 ether);
        // overage (1000 - 100) refunded immediately
        assertEq(quote.balanceOf(alice), balBefore + 900 ether);
    }

    function test_reveal_wrongSaltReverts() public {
        _commit(alice, 100 ether, 100 ether);
        vm.warp(COMMIT_END + 1);
        vm.prank(alice);
        vm.expectRevert(CommitRevealLaunch.BadReveal.selector);
        launch.reveal(id, 100 ether, keccak256("wrong"));
    }

    function test_reveal_amountAboveMaskReverts() public {
        // commit a hash for 200 but only escrow 100 → reveal(200) fails the mask check
        bytes32 c = launch.commitmentFor(200 ether, _salt(alice), alice);
        vm.prank(alice);
        launch.commit(id, c, 100 ether);
        vm.warp(COMMIT_END + 1);
        vm.prank(alice);
        vm.expectRevert(CommitRevealLaunch.MaskTooLow.selector);
        launch.reveal(id, 200 ether, _salt(alice));
    }

    function test_commit_outsideWindowReverts() public {
        vm.warp(COMMIT_END + 1);
        bytes32 c = launch.commitmentFor(1 ether, _salt(alice), alice);
        vm.prank(alice);
        vm.expectRevert(CommitRevealLaunch.NotInCommitWindow.selector);
        launch.commit(id, c, 1 ether);
    }

    function test_reveal_outsideWindowReverts() public {
        _commit(alice, 1 ether, 1 ether);
        // still in commit window
        vm.prank(alice);
        vm.expectRevert(CommitRevealLaunch.NotInRevealWindow.selector);
        launch.reveal(id, 1 ether, _salt(alice));
    }

    function test_doubleCommitReverts() public {
        _commit(alice, 1 ether, 10 ether);
        bytes32 c = launch.commitmentFor(2 ether, _salt(alice), alice);
        vm.prank(alice);
        vm.expectRevert(CommitRevealLaunch.AlreadyCommitted.selector);
        launch.commit(id, c, 10 ether);
    }

    function test_doubleRevealReverts() public {
        _commit(alice, 1 ether, 10 ether);
        vm.warp(COMMIT_END + 1);
        _reveal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(CommitRevealLaunch.AlreadyRevealed.selector);
        launch.reveal(id, 1 ether, _salt(alice));
    }

    // --- fairness: pro-rata on revealed bids, order-independent ---------------

    function test_proRata_onRevealedAmounts() public {
        _commit(alice, 100 ether, 100 ether);
        _commit(bob, 300 ether, 300 ether);
        vm.warp(COMMIT_END + 1);
        // reveal in "reverse" order — must not matter
        _reveal(bob, 300 ether);
        _reveal(alice, 100 ether);
        vm.warp(REVEAL_END + 1);
        launch.settle(id);

        assertEq(launch.totalRevealed(id), 400 ether);
        uint256 aliceAlloc = FullMath.mulDiv(OFFERED, 100 ether, 400 ether);
        uint256 bobAlloc = FullMath.mulDiv(OFFERED, 300 ether, 400 ether);

        vm.prank(alice);
        launch.claim(id);
        vm.prank(bob);
        launch.claim(id);
        assertEq(IERC20(token).balanceOf(alice), aliceAlloc);
        assertEq(IERC20(token).balanceOf(bob), bobAlloc);
        assertEq(bobAlloc, aliceAlloc * 3); // 300 vs 100
    }

    // --- unrevealed bidder: no allocation, escrow reclaimable -----------------

    function test_unrevealed_reclaimsAfterSuccess_noAllocation() public {
        _commit(alice, 100 ether, 100 ether);
        _commit(bob, 0, 500 ether); // bob commits a masked 500 but will never reveal
        vm.warp(COMMIT_END + 1);
        _reveal(alice, 100 ether);
        vm.warp(REVEAL_END + 1);

        uint256 bobBefore = quote.balanceOf(bob);
        launch.settle(id); // success (minRaise 0); totalRevealed = 100 (only alice)
        assertEq(launch.totalRevealed(id), 100 ether);

        // bob never revealed → no allocation: claim reverts before he's done anything
        vm.prank(bob);
        vm.expectRevert(CommitRevealLaunch.NothingToClaim.selector);
        launch.claim(id);

        // and bob reclaims his full masked deposit back
        vm.prank(bob);
        launch.reclaim(id);
        assertEq(quote.balanceOf(bob), bobBefore + 500 ether);
        assertEq(IERC20(token).balanceOf(bob), 0);
    }

    // --- failed launch: everyone reclaims, no pool --------------------------

    function test_failedLaunch_refundsAll() public {
        // minRaise above what gets revealed → failure
        vm.prank(launcher);
        (, , PoolId id2) = launch.createLaunch(
            CommitRevealLaunch.LaunchParams({
                name: "Fail",
                symbol: "F",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                commitEnd: COMMIT_END,
                revealEnd: REVEAL_END,
                minRaise: 1_000 ether,
                maxMaskedPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );
        bytes32 c = launch.commitmentFor(100 ether, _salt(alice), alice);
        vm.prank(alice);
        launch.commit(id2, c, 100 ether);
        vm.warp(COMMIT_END + 1);
        vm.prank(alice);
        launch.reveal(id2, 100 ether, _salt(alice));
        vm.warp(REVEAL_END + 1);

        uint256 aliceBefore = quote.balanceOf(alice);
        launch.settle(id2);
        CommitRevealLaunch.Launch memory l = launch.getLaunch(id2);
        assertTrue(l.failed);

        vm.prank(alice);
        launch.reclaim(id2);
        assertEq(quote.balanceOf(alice), aliceBefore + 100 ether);
    }

    // --- settlement seeds the pool at the clearing price + opens trading ------

    function test_settle_initializesPoolAtClearingPrice() public {
        _commit(alice, 200 ether, 200 ether);
        vm.warp(COMMIT_END + 1);
        _reveal(alice, 200 ether);
        vm.warp(REVEAL_END + 1);
        launch.settle(id);

        assertTrue(hook.isSettled(id));
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        assertEq(sqrtPriceX96, launch.clearingPrice(id));
        assertGt(sqrtPriceX96, 0);
    }

    function test_settle_beforeRevealCloseReverts() public {
        _commit(alice, 1 ether, 1 ether);
        vm.warp(COMMIT_END + 1);
        _reveal(alice, 1 ether);
        // reveal window still open
        vm.expectRevert(CommitRevealLaunch.WindowNotClosed.selector);
        launch.settle(id);
    }

    // ============================================================
    // v1.1 hardening — fixes #2, #3, #4, #9
    // ============================================================

    address launcherA = makeAddr("launcherA");
    address launcherB = makeAddr("launcherB");

    function _createWithEnd(string memory n, string memory s, uint64 cEnd, uint64 rEnd, uint256 minRaise, address who)
        internal
        returns (PoolId pid)
    {
        vm.prank(who);
        (, , pid) = launch.createLaunch(
            CommitRevealLaunch.LaunchParams({
                name: n,
                symbol: s,
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                commitEnd: cEnd,
                revealEnd: rEnd,
                minRaise: minRaise,
                maxMaskedPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );
    }

    /// @dev Finding #2: even with the v2 `quoteUsed`-based launcher payout, an extreme `lpTokens` /
    /// `offeredTokens` ratio or out-of-range price math could make `quoteUsed > totalRevealed`, draining
    /// other launches' escrow. The fix adds `require(quoteUsed <= totalRevealed)`.
    /// Also: with two launches sharing the same quote+manager, settling B must not pay launcher_B more
    /// than launch B's revealed raise (no sweep of A's escrow).
    function test_v11_settle_doesNotDrainOtherLaunchEscrow() public {
        uint64 cEndB = COMMIT_END;
        uint64 rEndB = REVEAL_END;
        uint64 cEndA = uint64(START + 3 hours);
        uint64 rEndA = uint64(START + 4 hours);

        PoolId idA = _createWithEnd("A", "A", cEndA, rEndA, 0, launcherA);
        PoolId idB = _createWithEnd("B", "B", cEndB, rEndB, 0, launcherB);

        // Alice commits to A (big), Bob to B (small).
        bytes32 cA = launch.commitmentFor(600 ether, _salt(alice), alice);
        vm.prank(alice);
        launch.commit(idA, cA, 600 ether);
        bytes32 cB = launch.commitmentFor(100 ether, _salt(bob), bob);
        vm.prank(bob);
        launch.commit(idB, cB, 100 ether);

        // Reveal both during their respective reveal windows. Bob first (B window opens first).
        vm.warp(cEndB + 1);
        vm.prank(bob);
        launch.reveal(idB, 100 ether, _salt(bob));

        // Settle B while A is still open. Before settling, the manager holds 600+100 quote.
        assertEq(quote.balanceOf(address(launch)), 700 ether);
        uint256 launcherBBefore = quote.balanceOf(launcherB);

        vm.warp(rEndB + 1);
        launch.settle(idB);

        // Launcher B got at most their own revealed raise (minus LP), never Alice's 600.
        uint256 launcherBGained = quote.balanceOf(launcherB) - launcherBBefore;
        assertLe(launcherBGained, 100 ether, "launcher B paid no more than launch B revealed");

        // Manager still holds Alice's full deposit so launch A is solvent.
        assertGe(quote.balanceOf(address(launch)), 600 ether, "launch A escrow preserved");

        // A still settleable end-to-end: reveal + settle + claim.
        vm.warp(cEndA + 1);
        vm.prank(alice);
        launch.reveal(idA, 600 ether, _salt(alice));
        vm.warp(rEndA + 1);
        launch.settle(idA);
        vm.prank(alice);
        launch.claim(idA);
        assertGt(IERC20(launch.getLaunch(idA).token).balanceOf(alice), 0, "Alice still claims her allocation");
    }

    /// @dev Finding #3: an out-of-range clearing price (extreme offered/revealed ratio) would brick settle
    /// pre-v1.1 because PoolManager.initialize reverted. The fix marks the launch failed so revealers can
    /// reclaim.
    function test_v11_settle_bricksOnBadPriceMarksFailed() public {
        vm.prank(launcher);
        (, , PoolId idBad) = launch.createLaunch(
            CommitRevealLaunch.LaunchParams({
                name: "BadPrice",
                symbol: "BAD",
                totalSupply: type(uint128).max,
                offeredTokens: type(uint128).max - 1, // huge denominator => clearing price ~ 0
                lpTokens: 1,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                commitEnd: COMMIT_END,
                revealEnd: REVEAL_END,
                minRaise: 0,
                maxMaskedPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );
        bytes32 c = launch.commitmentFor(1, _salt(alice), alice);
        vm.prank(alice);
        launch.commit(idBad, c, 1);
        vm.warp(COMMIT_END + 1);
        vm.prank(alice);
        launch.reveal(idBad, 1, _salt(alice));
        vm.warp(REVEAL_END + 1);

        // Should NOT brick.
        launch.settle(idBad);
        CommitRevealLaunch.Launch memory l = launch.getLaunch(idBad);
        assertTrue(l.settled);
        assertTrue(l.failed, "out-of-range clearing price marks launch failed");

        // Alice can reclaim her revealed bid via the failed-launch path.
        uint256 balBefore = quote.balanceOf(alice);
        vm.prank(alice);
        launch.reclaim(idBad);
        assertEq(quote.balanceOf(alice), balBefore + 1);
    }

    function test_v11_createLaunch_rejectsZeroTickSpacing() public {
        vm.prank(launcher);
        vm.expectRevert(CommitRevealLaunch.BadParams.selector);
        launch.createLaunch(
            CommitRevealLaunch.LaunchParams({
                name: "Zero",
                symbol: "ZTS",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(quote)),
                startTime: START,
                commitEnd: COMMIT_END,
                revealEnd: REVEAL_END,
                minRaise: 0,
                maxMaskedPerWallet: 0,
                tickSpacing: 0
            })
        );
    }

    /// @dev Finding #4: ERC-777-style reentrancy via the quote token's `transferFrom` hook must be blocked
    /// by `nonReentrant`. We try to reenter `commit` from within the masked-deposit transfer.
    function test_v11_commit_reentrancyBlocked() public {
        ReentrantQuoteToken evil = new ReentrantQuoteToken();
        vm.prank(launcher);
        (, , PoolId idEvil) = launch.createLaunch(
            CommitRevealLaunch.LaunchParams({
                name: "Evil",
                symbol: "EV",
                totalSupply: TOTAL_SUPPLY,
                offeredTokens: OFFERED,
                lpTokens: LP_TOKENS,
                quote: Currency.wrap(address(evil)),
                startTime: START,
                commitEnd: COMMIT_END,
                revealEnd: REVEAL_END,
                minRaise: 0,
                maxMaskedPerWallet: 0,
                tickSpacing: TICK_SPACING
            })
        );

        evil.mint(alice, 100 ether);
        vm.prank(alice);
        evil.approve(address(launch), type(uint256).max);
        bytes32 cm = launch.commitmentFor(10 ether, _salt(alice), alice);
        evil.armCommit(address(launch), idEvil, cm, 10 ether);

        vm.prank(alice);
        vm.expectRevert();
        launch.commit(idEvil, cm, 10 ether);
    }

    /// @dev Finding #9: configure() is allowlist-gated. A non-owner non-allowlisted manager calling
    /// configure on a fresh pool key must revert.
    function test_v11_configure_frontRunBlockedByAllowlist() public {
        PoolKey memory k =
            PoolKey(key.currency0, key.currency1, 3000, int24(120), IHooks(address(hook)));
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(SealedLaunchHook.ManagerNotAllowed.selector);
        hook.configure(k, START, REVEAL_END, attacker);
    }
}

// ============================================================================
// Malicious ERC-777-style quote token used by the v1.1 reentrancy test.
// ============================================================================

contract ReentrantQuoteToken {
    string public constant name = "Evil";
    string public constant symbol = "EVL";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    CommitRevealLaunch private _target;
    PoolId private _id;
    bytes32 private _cm;
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
            _target.commit(_id, _cm, _amt);
        }
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function armCommit(address target, PoolId id, bytes32 cm, uint256 amt) external {
        _target = CommitRevealLaunch(target);
        _id = id;
        _cm = cm;
        _amt = amt;
        _armed = true;
    }
}
