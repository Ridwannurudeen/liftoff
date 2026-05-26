// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
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
        deployCodeTo("SealedLaunchHook.sol:SealedLaunchHook", abi.encode(poolManager), flags);
        hook = SealedLaunchHook(flags);

        launch = new CommitRevealLaunch(poolManager, hook);
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
}
