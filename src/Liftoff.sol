// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/// @title Liftoff
/// @notice A "fair launch + fair life" Uniswap v4 hook for token launches on X Layer.
/// One hook runs the whole lifecycle of a launch pool:
///   1. Anti-snipe: a time-decaying launch fee on buys during the opening window + buy caps (per-tx and per-wallet).
///   2. Rug protection: liquidity removal is locked until `lpLockUntil`.
///   3. Graduation: once cumulative volume (or the window) is reached, the pool flips to the baseline fee.
///   4. Anti-dump: after graduation, sells are capped per tx, per wallet, and as a % of pool reserves.
/// The launched token launches *as* a v4 pool — no separate bonding-curve contract, no migration step.
///
/// @dev Per-wallet caps need the end user's address, but v4 passes the *router* as the swap `sender`. Liftoff
/// resolves the user from `hookData` when the swap comes through the trusted `LiftoffRouter`, and falls back to
/// `tx.origin` otherwise. `tx.origin` is best-effort (spoofable by a malicious router, breaks under account
/// abstraction); the trusted router is the reliable path. Cap enforcement runs in `_afterSwap` on the realized
/// `BalanceDelta`, so it is exact for both exact-input and exact-output swaps.
contract Liftoff is BaseHook {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    struct LaunchConfig {
        bool tokenIsCurrency0; // which side of the pool is the launched token
        uint24 startFee; // anti-snipe fee at window open (pips; 1_000_000 = 100%)
        uint24 endFee; // fee at window close (pips)
        uint24 baselineFee; // fee after graduation (pips)
        uint64 launchWindow; // anti-snipe window length, seconds
        uint256 maxBuyPerTx; // pre-graduation per-tx buy cap (quote-in units); 0 = disabled
        uint256 maxBuyPerWallet; // pre-graduation cumulative buy cap per wallet (quote-in units); 0 = disabled
        uint256 graduationVolume; // cumulative quote volume that triggers graduation
        uint64 lpLockUntil; // timestamp before which liquidity cannot be removed
        uint256 maxSellPerTx; // post-graduation per-tx sell cap (token-in units); 0 = disabled
        uint256 maxSellPerWallet; // post-graduation cumulative sell cap per wallet (token-in units); 0 = disabled
        uint16 maxSellBpsOfReserve; // post-graduation per-sell cap as bps of token reserve (1e4 = 100%); 0 = disabled
    }

    struct LaunchState {
        bool configured;
        bool graduated;
        uint64 launchStart;
        uint64 graduationTime;
        uint256 cumulativeVolume;
    }

    /// @notice The only router whose `hookData` is trusted to carry the end-user address for per-wallet caps.
    address public immutable trustedRouter;

    mapping(PoolId => LaunchConfig) public configs;
    mapping(PoolId => LaunchState) public states;

    /// @notice Cumulative quote spent buying, per pool, per wallet (pre-graduation accounting).
    mapping(PoolId => mapping(address => uint256)) public boughtBy;
    /// @notice Cumulative token sold, per pool, per wallet (post-graduation accounting).
    mapping(PoolId => mapping(address => uint256)) public soldBy;

    error AlreadyConfigured();
    error NotConfigured();
    error NotDynamicFee();
    error BadConfig();
    error BuyCapExceeded();
    error BuyWalletCapExceeded();
    error SellCapExceeded();
    error SellWalletCapExceeded();
    error SellReserveCapExceeded();
    error LiquidityLocked();

    event LaunchConfigured(PoolId indexed poolId, address indexed configurer);
    event Graduated(PoolId indexed poolId, uint256 cumulativeVolume, uint64 at);

    constructor(IPoolManager _poolManager, address _trustedRouter) BaseHook(_poolManager) {
        trustedRouter = _trustedRouter;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Configure a launch for a pool. Must be called before the pool is initialized.
    /// The pool must be a dynamic-fee pool (key.fee == LPFeeLibrary.DYNAMIC_FEE_FLAG).
    function configureLaunch(PoolKey calldata key, LaunchConfig calldata cfg) external {
        PoolId id = key.toId();
        if (states[id].configured) revert AlreadyConfigured();
        if (!key.fee.isDynamicFee()) revert NotDynamicFee();
        if (
            cfg.startFee < cfg.endFee || cfg.startFee > LPFeeLibrary.MAX_LP_FEE
                || cfg.baselineFee > LPFeeLibrary.MAX_LP_FEE || cfg.launchWindow == 0
                || cfg.maxSellBpsOfReserve > 10_000
        ) {
            revert BadConfig();
        }
        configs[id] = cfg;
        states[id].configured = true;
        emit LaunchConfigured(id, msg.sender);
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        PoolId id = key.toId();
        if (!states[id].configured) revert NotConfigured();
        states[id].launchStart = uint64(block.timestamp);
        return BaseHook.beforeInitialize.selector;
    }

    /// @dev Sets only the dynamic fee. All quantity caps are enforced in `_afterSwap` on realized amounts.
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId id = key.toId();
        LaunchConfig storage cfg = configs[id];
        LaunchState storage st = states[id];

        bool isBuy = cfg.tokenIsCurrency0 ? !params.zeroForOne : params.zeroForOne;

        uint24 fee;
        if (!st.graduated) {
            fee = isBuy ? _decayingFee(cfg, st) : cfg.endFee;
        } else {
            fee = cfg.baselineFee;
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function _afterSwap(address sender, PoolKey calldata key, SwapParams calldata, BalanceDelta delta, bytes calldata hookData)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        LaunchState storage st = states[id];
        bool wasGraduated = st.graduated;

        // Enforce caps on realized amounts (resolving the end user once) and accrue quote volume.
        st.cumulativeVolume += _processSwap(id, wasGraduated, delta, _resolveUser(sender, hookData));
        _maybeGraduate(id, st, wasGraduated);

        return (BaseHook.afterSwap.selector, int128(0));
    }

    /// @dev Enforces buy/sell caps on the realized `BalanceDelta` (exact for exact-in and exact-out) and
    /// returns the absolute quote volume of the swap. Split out of `_afterSwap` to keep its stack frame small.
    function _processSwap(PoolId id, bool graduated, BalanceDelta delta, address user)
        private
        returns (uint256 quoteVolume)
    {
        LaunchConfig storage cfg = configs[id];
        // Realized deltas from the swapper's perspective: positive = received, negative = paid.
        int256 tokenDelta = int256(cfg.tokenIsCurrency0 ? delta.amount0() : delta.amount1());
        int256 quoteDelta = int256(cfg.tokenIsCurrency0 ? delta.amount1() : delta.amount0());

        if (!graduated) {
            if (tokenDelta > 0) _enforceBuyCaps(id, cfg, uint256(-quoteDelta), user);
        } else {
            if (tokenDelta < 0) _enforceSellCaps(id, cfg, uint256(-tokenDelta), user);
        }

        quoteVolume = quoteDelta < 0 ? uint256(-quoteDelta) : uint256(quoteDelta);
    }

    function _maybeGraduate(PoolId id, LaunchState storage st, bool wasGraduated) private {
        if (wasGraduated) return;
        LaunchConfig storage cfg = configs[id];
        if (st.cumulativeVolume >= cfg.graduationVolume || block.timestamp >= st.launchStart + cfg.launchWindow) {
            st.graduated = true;
            st.graduationTime = uint64(block.timestamp);
            emit Graduated(id, st.cumulativeVolume, st.graduationTime);
        }
    }

    function _enforceBuyCaps(PoolId id, LaunchConfig storage cfg, uint256 buyIn, address user) private {
        if (cfg.maxBuyPerTx != 0 && buyIn > cfg.maxBuyPerTx) revert BuyCapExceeded();
        if (cfg.maxBuyPerWallet != 0) {
            uint256 total = boughtBy[id][user] + buyIn;
            if (total > cfg.maxBuyPerWallet) revert BuyWalletCapExceeded();
            boughtBy[id][user] = total;
        }
    }

    function _enforceSellCaps(PoolId id, LaunchConfig storage cfg, uint256 sellIn, address user) private {
        if (cfg.maxSellPerTx != 0 && sellIn > cfg.maxSellPerTx) revert SellCapExceeded();
        if (cfg.maxSellPerWallet != 0) {
            uint256 total = soldBy[id][user] + sellIn;
            if (total > cfg.maxSellPerWallet) revert SellWalletCapExceeded();
            soldBy[id][user] = total;
        }
        if (cfg.maxSellBpsOfReserve != 0) {
            uint256 postReserve = _tokenReserve(id, cfg.tokenIsCurrency0);
            // A sell adds tokens to the pool, so the pre-swap reserve is the realized reserve minus this sell.
            uint256 preReserve = postReserve > sellIn ? postReserve - sellIn : 0;
            if (preReserve != 0 && sellIn > FullMath.mulDiv(preReserve, cfg.maxSellBpsOfReserve, 10_000)) {
                revert SellReserveCapExceeded();
            }
        }
    }

    /// @dev The end-user identity for per-wallet caps. Decoded from `hookData` only when the trusted router
    /// is the swap caller; otherwise falls back to `tx.origin` (best-effort; see contract notice).
    function _resolveUser(address sender, bytes calldata hookData) private view returns (address) {
        if (sender == trustedRouter && hookData.length >= 32) {
            return abi.decode(hookData, (address));
        }
        return tx.origin;
    }

    function _decayingFee(LaunchConfig storage cfg, LaunchState storage st) internal view returns (uint24) {
        uint256 elapsed = block.timestamp - st.launchStart;
        if (elapsed >= cfg.launchWindow) return cfg.endFee;
        uint256 drop = (uint256(cfg.startFee - cfg.endFee) * elapsed) / cfg.launchWindow;
        return uint24(uint256(cfg.startFee) - drop);
    }

    function _tokenReserve(PoolId id, bool tokenIsCurrency0) internal view returns (uint256) {
        uint128 liquidity = poolManager.getLiquidity(id);
        if (liquidity == 0) return 0;
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        if (sqrtPriceX96 == 0) return 0;
        uint256 q96 = 1 << 96;
        // Full-range reserves: x = L / sqrtP (token0), y = L * sqrtP (token1). LaunchFactory pools are
        // full-range, so this is the constant-product-equivalent reserve at the current price.
        return tokenIsCurrency0
            ? FullMath.mulDiv(liquidity, q96, sqrtPriceX96)
            : FullMath.mulDiv(liquidity, sqrtPriceX96, q96);
    }

    function _beforeRemoveLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        if (block.timestamp < configs[key.toId()].lpLockUntil) revert LiquidityLocked();
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    // --- views ---------------------------------------------------------------

    /// @notice The LP fee that a buy would currently pay (pips), ignoring the override flag.
    function currentBuyFee(PoolId id) external view returns (uint24) {
        LaunchState storage st = states[id];
        if (st.graduated) return configs[id].baselineFee;
        return _decayingFee(configs[id], st);
    }
}
