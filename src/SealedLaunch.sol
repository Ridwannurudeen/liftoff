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
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {LaunchToken} from "./LaunchToken.sol";
import {SealedLaunchHook} from "./SealedLaunchHook.sol";

/// @title SealedLaunch
/// @notice Factory + escrow + settlement for a uniform-price sealed batch-auction token launch.
/// Buyers commit quote tokens during the launch window; ordinary swaps are blocked by `SealedLaunchHook`
/// the whole time. At window close everyone clears at ONE uniform price, pro-rata to their commitment —
/// commit order and block position are irrelevant, so unpredictable X Layer (flashblock) ordering buys no
/// advantage. After settlement the pool is initialized at the clearing price, seeded with liquidity, and
/// opened for normal trading. If the raise misses `minRaise`, no pool is created and commitments are refundable.
contract SealedLaunch is IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeERC20 for IERC20;

    /// @notice Static LP fee for the launched pool (0.3%). The auction sets the price; the pool just trades.
    uint24 public constant LP_FEE = 3000;

    IPoolManager public immutable poolManager;
    SealedLaunchHook public immutable hook;

    struct LaunchParams {
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 offeredTokens; // sold to bidders, distributed pro-rata
        uint256 lpTokens; // seeded into the pool at settlement
        Currency quote;
        uint64 startTime;
        uint64 endTime;
        uint256 minRaise; // launch fails if totalCommitted < minRaise
        uint256 maxCommitPerWallet; // 0 = disabled
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
        uint64 endTime;
        uint256 minRaise;
        uint256 maxCommitPerWallet;
        int24 tickSpacing;
        bool tokenIsCurrency0;
        bool settled;
        bool failed;
        uint256 totalCommitted;
        uint160 clearingSqrtPriceX96; // pool price at settlement (0 until a successful settle)
    }

    mapping(PoolId => Launch) internal launches;
    mapping(PoolId => mapping(address => uint256)) public committed;
    mapping(PoolId => mapping(address => bool)) public claimed;

    /// @dev Transient: the PoolKey being seeded inside `unlockCallback`.
    PoolKey private _activeKey;

    error AlreadyExists();
    error BadParams();
    error NotPoolManager();
    error LaunchNotFound();
    error NotInWindow();
    error AlreadySettled();
    error WindowNotClosed();
    error WalletCapExceeded();
    error ZeroAmount();
    error NotSettled();
    error LaunchFailed();
    error LaunchSucceeded();
    error AlreadyClaimed();
    error NothingToClaim();
    error NothingToRefund();

    event LaunchCreated(PoolId indexed id, address indexed token, address indexed launcher, PoolKey key);
    event Committed(PoolId indexed id, address indexed user, uint256 amount, uint256 totalCommitted);
    event Settled(PoolId indexed id, uint160 clearingSqrtPriceX96, uint256 totalCommitted);
    event LaunchFailedEvent(PoolId indexed id, uint256 totalCommitted);
    event Claimed(PoolId indexed id, address indexed user, uint256 tokenAmount);
    event Refunded(PoolId indexed id, address indexed user, uint256 amount);

    constructor(IPoolManager _poolManager, SealedLaunchHook _hook) {
        poolManager = _poolManager;
        hook = _hook;
    }

    /// @notice Deploy the token, build + configure the launch pool (NOT initialized yet — the pool is
    /// initialized at settlement so its price equals the clearing price), and open commitments.
    function createLaunch(LaunchParams calldata p) external returns (address token, PoolKey memory key, PoolId id) {
        if (p.offeredTokens == 0 || p.lpTokens == 0) revert BadParams();
        if (p.totalSupply < p.offeredTokens + p.lpTokens) revert BadParams();
        if (p.endTime <= p.startTime) revert BadParams();

        // Full supply minted to this contract: it distributes to bidders (claim), seeds the LP, and sends
        // any remainder to the launcher at settlement.
        token = address(new LaunchToken(p.name, p.symbol, p.totalSupply, address(this)));

        bool tokenIsCurrency0 = token < Currency.unwrap(p.quote);
        (Currency c0, Currency c1) =
            tokenIsCurrency0 ? (Currency.wrap(token), p.quote) : (p.quote, Currency.wrap(token));
        key = PoolKey(c0, c1, LP_FEE, p.tickSpacing, IHooks(address(hook)));
        id = key.toId();

        if (launches[id].token != address(0)) revert AlreadyExists();

        hook.configure(key, p.startTime, p.endTime, address(this));

        launches[id] = Launch({
            token: token,
            quote: p.quote,
            launcher: msg.sender,
            totalSupply: p.totalSupply,
            offeredTokens: p.offeredTokens,
            lpTokens: p.lpTokens,
            startTime: p.startTime,
            endTime: p.endTime,
            minRaise: p.minRaise,
            maxCommitPerWallet: p.maxCommitPerWallet,
            tickSpacing: p.tickSpacing,
            tokenIsCurrency0: tokenIsCurrency0,
            settled: false,
            failed: false,
            totalCommitted: 0,
            clearingSqrtPriceX96: 0
        });

        emit LaunchCreated(id, token, msg.sender, key);
    }

    /// @notice Commit `amount` of quote to a launch. Pro-rata of the offered tokens is what you receive at
    /// settlement; order and block position are irrelevant.
    function commit(PoolId id, uint256 amount) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp < l.startTime || block.timestamp > l.endTime) revert NotInWindow();
        if (l.settled) revert AlreadySettled();

        uint256 newCommit = committed[id][msg.sender] + amount;
        if (l.maxCommitPerWallet != 0 && newCommit > l.maxCommitPerWallet) revert WalletCapExceeded();

        IERC20(Currency.unwrap(l.quote)).safeTransferFrom(msg.sender, address(this), amount);
        committed[id][msg.sender] = newCommit;
        l.totalCommitted += amount;

        emit Committed(id, msg.sender, amount, l.totalCommitted);
    }

    /// @notice Close the auction. If the raise missed `minRaise`, the launch fails and commitments become
    /// refundable. Otherwise the pool is initialized at the clearing price, seeded with LP, and opened.
    function settle(PoolId id) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (l.settled) revert AlreadySettled();
        if (block.timestamp <= l.endTime) revert WindowNotClosed();

        l.settled = true;

        if (l.totalCommitted < l.minRaise) {
            l.failed = true;
            emit LaunchFailedEvent(id, l.totalCommitted);
            return;
        }

        // Uniform clearing price P = quote per token = totalCommitted / offeredTokens.
        // v4 pool price is currency1 per currency0. sqrtPriceX96 = sqrt(price) * 2^96.
        // To avoid intermediate overflow we compute sqrt(FullMath.mulDiv(num, 2^192, den)); the result fits
        // in uint160 for any price the auction can produce.
        uint160 sqrtPriceX96 = l.tokenIsCurrency0
            ? _sqrtPriceX96(l.totalCommitted, l.offeredTokens) // price = quote/token = P
            : _sqrtPriceX96(l.offeredTokens, l.totalCommitted); // price = token/quote = 1/P
        l.clearingSqrtPriceX96 = sqrtPriceX96;

        PoolKey memory key = _keyOf(l);
        poolManager.initialize(key, sqrtPriceX96);

        // Seed full-range liquidity from the lpTokens side; the matching quote is whatever the pool requires
        // at the clearing price, pulled from this contract's balance inside the callback.
        _activeKey = key;
        poolManager.unlock(abi.encode(sqrtPriceX96));
        delete _activeKey;

        hook.markSettled(id);

        // Forward all raised quote not consumed by LP seeding to the launcher.
        uint256 quoteLeft = IERC20(Currency.unwrap(l.quote)).balanceOf(address(this));
        if (quoteLeft != 0) IERC20(Currency.unwrap(l.quote)).safeTransfer(l.launcher, quoteLeft);

        // Send any token remainder (totalSupply - offeredTokens - lpTokens, plus LP-seeding dust) to launcher.
        uint256 tokenLeft = IERC20(l.token).balanceOf(address(this)) - l.offeredTokens;
        if (tokenLeft != 0) IERC20(l.token).safeTransfer(l.launcher, tokenLeft);

        emit Settled(id, sqrtPriceX96, l.totalCommitted);
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        uint160 sqrtPriceX96 = abi.decode(raw, (uint160));
        PoolKey memory key = _activeKey;
        Launch storage l = launches[key.toId()];

        int24 tickLower = TickMath.minUsableTick(key.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(key.tickSpacing);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // Liquidity is sized off the lpTokens side so exactly `lpTokens` of token are committed to the pool.
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

        return "";
    }

    /// @notice Claim your pro-rata token allocation after a successful settlement.
    function claim(PoolId id) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (!l.settled) revert NotSettled();
        if (l.failed) revert LaunchFailed();
        if (claimed[id][msg.sender]) revert AlreadyClaimed();

        uint256 c = committed[id][msg.sender];
        if (c == 0) revert NothingToClaim();

        uint256 allocation = FullMath.mulDiv(l.offeredTokens, c, l.totalCommitted);
        claimed[id][msg.sender] = true;
        IERC20(l.token).safeTransfer(msg.sender, allocation);

        emit Claimed(id, msg.sender, allocation);
    }

    /// @notice Reclaim your committed quote after a failed launch.
    function refund(PoolId id) external {
        Launch storage l = launches[id];
        if (l.token == address(0)) revert LaunchNotFound();
        if (!l.failed) revert LaunchSucceeded();

        uint256 c = committed[id][msg.sender];
        if (c == 0) revert NothingToRefund();

        committed[id][msg.sender] = 0;
        IERC20(Currency.unwrap(l.quote)).safeTransfer(msg.sender, c);

        emit Refunded(id, msg.sender, c);
    }

    // --- price math ----------------------------------------------------------

    /// @dev sqrtPriceX96 for pool price = numerator/denominator (in raw token units), as a Q64.96 sqrt.
    function _sqrtPriceX96(uint256 numerator, uint256 denominator) internal pure returns (uint160) {
        uint256 priceX192 = FullMath.mulDiv(numerator, 1 << 192, denominator);
        return uint160(FixedPointMathLib.sqrt(priceX192));
    }

    // --- views ---------------------------------------------------------------

    function getLaunch(PoolId id) external view returns (Launch memory) {
        return launches[id];
    }

    function clearingPrice(PoolId id) external view returns (uint160 sqrtPriceX96) {
        return launches[id].clearingSqrtPriceX96;
    }

    function totalCommitted(PoolId id) external view returns (uint256) {
        return launches[id].totalCommitted;
    }

    /// @notice The token allocation `user` would receive at claim (after a successful settlement).
    function allocationOf(PoolId id, address user) external view returns (uint256) {
        Launch storage l = launches[id];
        if (l.totalCommitted == 0) return 0;
        return FullMath.mulDiv(l.offeredTokens, committed[id][user], l.totalCommitted);
    }

    function _keyOf(Launch storage l) internal view returns (PoolKey memory) {
        (Currency c0, Currency c1) = l.tokenIsCurrency0
            ? (Currency.wrap(l.token), l.quote)
            : (l.quote, Currency.wrap(l.token));
        return PoolKey(c0, c1, LP_FEE, l.tickSpacing, IHooks(address(hook)));
    }
}
