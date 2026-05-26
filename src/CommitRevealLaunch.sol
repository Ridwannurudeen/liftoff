// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {LaunchToken} from "./LaunchToken.sol";
import {SealedLaunchHook} from "./SealedLaunchHook.sol";

/// @title CommitRevealLaunch
/// @notice Sealed-bid (commit-reveal) uniform-price batch-auction token launch — v2 of Sealed Launch.
/// v1 (`SealedLaunch`) is order-independent but commitment *amounts* are visible on-chain. This variant
/// hides bid sizes until settlement: bidders post `keccak256(amount, salt, bidder)` and escrow a *masked*
/// deposit (an upper bound on their bid) during the commit window; they later `reveal` the real amount and
/// salt, and the overpayment is refunded. The pool stays gated by `SealedLaunchHook` until settle, so the
/// auction still clears at one uniform price, pro-rata to revealed bids — now with sealed sizes too.
/// @dev The pool gating hook is reused unchanged. Escrow accounting: each committer's masked deposit is held
/// until they reveal (overage refunded, `amount` retained) or, post-settle, reclaim it (no reveal → no
/// allocation). The "free option" of committing then not revealing if the price turns unfavorable is a known
/// trade-off (no reveal forfeiture); see ROADMAP.
contract CommitRevealLaunch is IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencySettler for Currency;
    using SafeERC20 for IERC20;

    uint24 public constant LP_FEE = 3000;

    IPoolManager public immutable poolManager;
    SealedLaunchHook public immutable hook;

    struct LaunchParams {
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 offeredTokens;
        uint256 lpTokens;
        Currency quote;
        uint64 startTime;
        uint64 commitEnd; // commit window: [startTime, commitEnd]
        uint64 revealEnd; // reveal window: (commitEnd, revealEnd]
        uint256 minRaise;
        uint256 maxMaskedPerWallet; // 0 = disabled; caps the masked deposit (hence max possible bid)
        int24 tickSpacing;
    }

    struct Launch {
        address token;
        Currency quote;
        address launcher;
        uint256 totalSupply;
        uint256 offeredTokens;
        uint256 lpTokens;
        uint64 startTime;
        uint64 commitEnd;
        uint64 revealEnd;
        uint256 minRaise;
        uint256 maxMaskedPerWallet;
        int24 tickSpacing;
        bool tokenIsCurrency0;
        bool settled;
        bool failed;
        uint256 totalRevealed; // clearing denominator (sum of revealed bids)
        uint160 clearingSqrtPriceX96;
    }

    struct Bid {
        bytes32 commitment; // keccak256(abi.encode(amount, salt, bidder))
        uint256 masked; // quote escrowed at commit (>= revealed amount)
        uint256 revealed; // real bid, set at reveal
        bool didReveal;
        bool settledOut; // claimed / refunded / reclaimed — escrow returned or allocation taken
    }

    mapping(PoolId => Launch) internal launches;
    mapping(PoolId => mapping(address => Bid)) internal bids;

    PoolId private _activeId;
    uint256 private _quoteUsed; // quote consumed by LP seeding inside the unlock callback

    error AlreadyExists();
    error BadParams();
    error NotPoolManager();
    error LaunchNotFound();
    error NotInCommitWindow();
    error NotInRevealWindow();
    error AlreadyCommitted();
    error NothingCommitted();
    error AlreadyRevealed();
    error BadReveal();
    error MaskTooLow();
    error WalletCapExceeded();
    error ZeroCommitment();
    error WindowNotClosed();
    error AlreadySettled();
    error NotSettled();
    error LaunchFailed();
    error LaunchSucceeded();
    error AlreadySettledOut();
    error NothingToClaim();

    event LaunchCreated(PoolId indexed id, address indexed token, address indexed launcher, PoolKey key);
    event Committed(PoolId indexed id, address indexed user, uint256 masked);
    event Revealed(PoolId indexed id, address indexed user, uint256 amount, uint256 refundedOverage);
    event Settled(PoolId indexed id, uint160 clearingSqrtPriceX96, uint256 totalRevealed);
    event LaunchFailedEvent(PoolId indexed id, uint256 totalRevealed);
    event Claimed(PoolId indexed id, address indexed user, uint256 tokenAmount);
    event Refunded(PoolId indexed id, address indexed user, uint256 amount);

    constructor(IPoolManager _poolManager, SealedLaunchHook _hook) {
        poolManager = _poolManager;
        hook = _hook;
    }

    /// @notice Compute the commitment a bidder must post: keccak256(amount, salt, bidder).
    function commitmentFor(uint256 amount, bytes32 salt, address bidder) public pure returns (bytes32) {
        return keccak256(abi.encode(amount, salt, bidder));
    }

    /// @notice Deploy the token, configure the (uninitialized) launch pool, and open the commit window.
    function createLaunch(LaunchParams calldata p) external returns (address token, PoolKey memory key, PoolId id) {
        if (p.offeredTokens == 0 || p.lpTokens == 0) revert BadParams();
        if (p.totalSupply < p.offeredTokens + p.lpTokens) revert BadParams();
        if (!(p.startTime < p.commitEnd && p.commitEnd < p.revealEnd)) revert BadParams();

        token = address(new LaunchToken(p.name, p.symbol, p.totalSupply, address(this)));

        bool tokenIsCurrency0 = token < Currency.unwrap(p.quote);
        (Currency c0, Currency c1) =
            tokenIsCurrency0 ? (Currency.wrap(token), p.quote) : (p.quote, Currency.wrap(token));
        key = PoolKey(c0, c1, LP_FEE, p.tickSpacing, IHooks(address(hook)));
        id = key.toId();
        if (launches[id].token != address(0)) revert AlreadyExists();

        // Hook gates the pool until settle; it only needs the overall window end (revealEnd).
        hook.configure(key, p.startTime, p.revealEnd, address(this));

        launches[id] = Launch({
            token: token,
            quote: p.quote,
            launcher: msg.sender,
            totalSupply: p.totalSupply,
            offeredTokens: p.offeredTokens,
            lpTokens: p.lpTokens,
            startTime: p.startTime,
            commitEnd: p.commitEnd,
            revealEnd: p.revealEnd,
            minRaise: p.minRaise,
            maxMaskedPerWallet: p.maxMaskedPerWallet,
            tickSpacing: p.tickSpacing,
            tokenIsCurrency0: tokenIsCurrency0,
            settled: false,
            failed: false,
            totalRevealed: 0,
            clearingSqrtPriceX96: 0
        });

        emit LaunchCreated(id, token, msg.sender, key);
    }

    /// @notice Commit a sealed bid: post `commitment` and escrow `masked` quote (an upper bound on your bid).
    /// One commit per wallet. Reveal later with the real amount + salt.
    function commit(PoolId id, bytes32 commitment, uint256 masked) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (commitment == bytes32(0)) revert ZeroCommitment();
        if (masked == 0) revert MaskTooLow();
        if (block.timestamp < l.startTime || block.timestamp > l.commitEnd) revert NotInCommitWindow();
        if (l.maxMaskedPerWallet != 0 && masked > l.maxMaskedPerWallet) revert WalletCapExceeded();

        Bid storage b = bids[id][msg.sender];
        if (b.commitment != bytes32(0)) revert AlreadyCommitted();

        b.commitment = commitment;
        b.masked = masked;
        IERC20(Currency.unwrap(l.quote)).safeTransferFrom(msg.sender, address(this), masked);

        emit Committed(id, msg.sender, masked);
    }

    /// @notice Reveal your real bid. Verifies the commitment, records `amount` as your bid, and refunds the
    /// masked overage (`masked - amount`). `amount` may be 0 to withdraw fully with no allocation.
    function reveal(PoolId id, uint256 amount, bytes32 salt) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (block.timestamp <= l.commitEnd || block.timestamp > l.revealEnd) revert NotInRevealWindow();

        Bid storage b = bids[id][msg.sender];
        if (b.commitment == bytes32(0)) revert NothingCommitted();
        if (b.didReveal) revert AlreadyRevealed();
        if (commitmentFor(amount, salt, msg.sender) != b.commitment) revert BadReveal();
        if (amount > b.masked) revert MaskTooLow();

        b.didReveal = true;
        b.revealed = amount;
        l.totalRevealed += amount;

        uint256 overage = b.masked - amount;
        if (overage != 0) IERC20(Currency.unwrap(l.quote)).safeTransfer(msg.sender, overage);

        emit Revealed(id, msg.sender, amount, overage);
    }

    /// @notice Close the auction after the reveal window. Clears at the uniform price on revealed bids, seeds
    /// the pool, and opens trading — or fails if revealed raise < minRaise (everyone reclaims).
    function settle(PoolId id) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (l.settled) revert AlreadySettled();
        if (block.timestamp <= l.revealEnd) revert WindowNotClosed();

        l.settled = true;

        if (l.totalRevealed < l.minRaise) {
            l.failed = true;
            emit LaunchFailedEvent(id, l.totalRevealed);
            return;
        }

        uint160 sqrtPriceX96 = l.tokenIsCurrency0
            ? _sqrtPriceX96(l.totalRevealed, l.offeredTokens)
            : _sqrtPriceX96(l.offeredTokens, l.totalRevealed);
        l.clearingSqrtPriceX96 = sqrtPriceX96;

        PoolKey memory key = _keyOf(l);
        poolManager.initialize(key, sqrtPriceX96);

        _activeId = id;
        _quoteUsed = 0;
        poolManager.unlock(abi.encode(sqrtPriceX96));
        uint256 quoteUsed = _quoteUsed;
        _activeId = PoolId.wrap(bytes32(0));
        _quoteUsed = 0;

        hook.markSettled(id);

        // Pay the launcher the revealed raise minus what LP seeding consumed. Unrevealed masked deposits stay
        // escrowed for their owners to reclaim — do NOT sweep the whole balance.
        uint256 launcherProceeds = l.totalRevealed > quoteUsed ? l.totalRevealed - quoteUsed : 0;
        if (launcherProceeds != 0) IERC20(Currency.unwrap(l.quote)).safeTransfer(l.launcher, launcherProceeds);

        uint256 tokenLeft = IERC20(l.token).balanceOf(address(this)) - l.offeredTokens;
        if (tokenLeft != 0) IERC20(l.token).safeTransfer(l.launcher, tokenLeft);

        emit Settled(id, sqrtPriceX96, l.totalRevealed);
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        uint160 sqrtPriceX96 = abi.decode(raw, (uint160));
        PoolKey memory key = _keyOf(launches[_activeId]);
        Launch storage l = launches[_activeId];

        int24 tickLower = TickMath.minUsableTick(key.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(key.tickSpacing);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liquidity = l.tokenIsCurrency0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtUpper, l.lpTokens)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtPriceX96, l.lpTokens);

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            ""
        );

        int256 d0 = int256(delta.amount0());
        int256 d1 = int256(delta.amount1());
        if (d0 < 0) key.currency0.settle(poolManager, address(this), uint256(-d0), false);
        if (d1 < 0) key.currency1.settle(poolManager, address(this), uint256(-d1), false);
        if (d0 > 0) key.currency0.take(poolManager, address(this), uint256(d0), false);
        if (d1 > 0) key.currency1.take(poolManager, address(this), uint256(d1), false);

        // Record how much QUOTE the seeding consumed so settle() can pay the launcher the remainder.
        bool quoteIsC0 = !l.tokenIsCurrency0;
        int256 quoteDelta = quoteIsC0 ? d0 : d1;
        _quoteUsed = quoteDelta < 0 ? uint256(-quoteDelta) : 0;

        return "";
    }

    /// @notice Claim your pro-rata token allocation after a successful settlement (revealers only).
    function claim(PoolId id) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (!l.settled) revert NotSettled();
        if (l.failed) revert LaunchFailed();

        Bid storage b = bids[id][msg.sender];
        if (b.settledOut) revert AlreadySettledOut();
        if (!b.didReveal || b.revealed == 0) revert NothingToClaim();

        uint256 allocation = FullMath.mulDiv(l.offeredTokens, b.revealed, l.totalRevealed);
        b.settledOut = true;
        IERC20(l.token).safeTransfer(msg.sender, allocation);

        emit Claimed(id, msg.sender, allocation);
    }

    /// @notice Reclaim escrow when you get no allocation: after a successful settle if you never revealed
    /// (returns your masked deposit), or after a failed launch (returns revealed bid, else masked deposit).
    function reclaim(PoolId id) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (!l.settled) revert NotSettled();

        Bid storage b = bids[id][msg.sender];
        if (b.commitment == bytes32(0)) revert NothingCommitted();
        if (b.settledOut) revert AlreadySettledOut();

        uint256 amount;
        if (l.failed) {
            amount = b.didReveal ? b.revealed : b.masked;
        } else {
            // success: only un-revealed bidders reclaim here (revealers use claim()).
            if (b.didReveal) revert LaunchSucceeded();
            amount = b.masked;
        }

        b.settledOut = true;
        if (amount != 0) IERC20(Currency.unwrap(l.quote)).safeTransfer(msg.sender, amount);

        emit Refunded(id, msg.sender, amount);
    }

    // --- price math ----------------------------------------------------------

    function _sqrtPriceX96(uint256 numerator, uint256 denominator) internal pure returns (uint160) {
        uint256 priceX192 = FullMath.mulDiv(numerator, 1 << 192, denominator);
        return uint160(FixedPointMathLib.sqrt(priceX192));
    }

    // --- views ---------------------------------------------------------------

    function getLaunch(PoolId id) external view returns (Launch memory) {
        return launches[id];
    }

    function getBid(PoolId id, address user) external view returns (Bid memory) {
        return bids[id][user];
    }

    function clearingPrice(PoolId id) external view returns (uint160) {
        return launches[id].clearingSqrtPriceX96;
    }

    function totalRevealed(PoolId id) external view returns (uint256) {
        return launches[id].totalRevealed;
    }

    function allocationOf(PoolId id, address user) external view returns (uint256) {
        Launch storage l = launches[id];
        if (l.totalRevealed == 0) return 0;
        return FullMath.mulDiv(l.offeredTokens, bids[id][user].revealed, l.totalRevealed);
    }

    function _keyOf(Launch storage l) internal view returns (PoolKey memory) {
        (Currency c0, Currency c1) =
            l.tokenIsCurrency0 ? (Currency.wrap(l.token), l.quote) : (l.quote, Currency.wrap(l.token));
        return PoolKey(c0, c1, LP_FEE, l.tickSpacing, IHooks(address(hook)));
    }
}
