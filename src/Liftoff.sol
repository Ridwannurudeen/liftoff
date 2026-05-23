// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/// @title Liftoff
/// @notice A "fair launch + fair life" Uniswap v4 hook for token launches on X Layer.
/// One hook runs the whole lifecycle of a launch pool:
///   1. Anti-snipe: a time-decaying launch fee on buys during the opening window + a per-tx buy cap.
///   2. Rug protection: liquidity removal is locked until `lpLockUntil`.
///   3. Graduation: once cumulative volume (or the window) is reached, the pool flips to the baseline fee.
///   4. Anti-dump: after graduation, sells are capped per tx to prevent cliff dumps.
/// The launched token launches *as* a v4 pool — no separate bonding-curve contract, no migration step.
contract Liftoff is BaseHook {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;

    struct LaunchConfig {
        bool tokenIsCurrency0; // which side of the pool is the launched token
        uint24 startFee; // anti-snipe fee at window open (pips; 1_000_000 = 100%)
        uint24 endFee; // fee at window close (pips)
        uint24 baselineFee; // fee after graduation (pips)
        uint64 launchWindow; // anti-snipe window length, seconds
        uint256 maxBuyPerTx; // pre-graduation per-tx buy cap (input units); 0 = disabled
        uint256 graduationVolume; // cumulative quote volume that triggers graduation
        uint64 lpLockUntil; // timestamp before which liquidity cannot be removed
        uint256 maxSellPerTx; // post-graduation per-tx sell cap (input units); 0 = disabled
    }

    struct LaunchState {
        bool configured;
        bool graduated;
        uint64 launchStart;
        uint64 graduationTime;
        uint256 cumulativeVolume;
    }

    mapping(PoolId => LaunchConfig) public configs;
    mapping(PoolId => LaunchState) public states;

    error AlreadyConfigured();
    error NotConfigured();
    error NotDynamicFee();
    error BadConfig();
    error BuyCapExceeded();
    error SellCapExceeded();
    error LiquidityLocked();

    event LaunchConfigured(PoolId indexed poolId, address indexed configurer);
    event Graduated(PoolId indexed poolId, uint256 cumulativeVolume, uint64 at);

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

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
        uint256 absAmt =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        uint24 fee;
        if (!st.graduated) {
            if (isBuy) {
                if (cfg.maxBuyPerTx != 0 && absAmt > cfg.maxBuyPerTx) revert BuyCapExceeded();
                fee = _decayingFee(cfg, st);
            } else {
                fee = cfg.endFee;
            }
        } else {
            if (!isBuy && cfg.maxSellPerTx != 0 && absAmt > cfg.maxSellPerTx) revert SellCapExceeded();
            fee = cfg.baselineFee;
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        LaunchConfig storage cfg = configs[id];
        LaunchState storage st = states[id];

        int256 q = int256(cfg.tokenIsCurrency0 ? delta.amount1() : delta.amount0());
        st.cumulativeVolume += q < 0 ? uint256(-q) : uint256(q);

        if (
            !st.graduated
                && (st.cumulativeVolume >= cfg.graduationVolume || block.timestamp >= st.launchStart + cfg.launchWindow)
        ) {
            st.graduated = true;
            st.graduationTime = uint64(block.timestamp);
            emit Graduated(id, st.cumulativeVolume, st.graduationTime);
        }

        return (BaseHook.afterSwap.selector, int128(0));
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

    function _decayingFee(LaunchConfig storage cfg, LaunchState storage st) internal view returns (uint24) {
        uint256 elapsed = block.timestamp - st.launchStart;
        if (elapsed >= cfg.launchWindow) return cfg.endFee;
        uint256 drop = (uint256(cfg.startFee - cfg.endFee) * elapsed) / cfg.launchWindow;
        return uint24(uint256(cfg.startFee) - drop);
    }
}
