// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/// @title SealedLaunchHook
/// @notice Gating hook for a uniform-price sealed batch-auction token launch on X Layer.
/// During the launch window ordinary swaps are blocked: nobody can trade the token until the auction
/// clears at a single uniform price, so unpredictable flashblock ordering buys no advantage. Liquidity
/// can only be seeded by the launch manager (the `SealedLaunch` contract); everyone else is locked out
/// of add-liquidity until settlement so the LP can't be front-run. After the manager settles, the pool
/// opens for normal trading.
///
/// @dev One hook serves every launch pool; per-pool config and state live in mappings keyed by `PoolId`.
/// The hook itself holds no funds and runs no price math — that all lives in `SealedLaunch`. This hook is
/// purely the access-control gate around the v4 pool.
contract SealedLaunchHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    struct LaunchInfo {
        address manager; // the SealedLaunch contract allowed to seed liquidity and settle
        uint64 startTime;
        uint64 endTime;
        bool settled;
    }

    mapping(PoolId => LaunchInfo) internal _launches;

    error AlreadyConfigured();
    error NotConfigured();
    error NotManager();
    error BadConfig();
    error SwapsLockedUntilSettled();
    error AddLiquidityLockedUntilSettled();
    error AlreadySettled();

    event LaunchConfigured(PoolId indexed poolId, address indexed manager, uint64 startTime, uint64 endTime);
    event Settled(PoolId indexed poolId);

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Configure a launch for a pool. Callable once per pool, before the pool is initialized,
    /// and only by the manager that will run the auction.
    function configure(PoolKey calldata key, uint64 startTime, uint64 endTime, address manager) external {
        PoolId id = key.toId();
        if (_launches[id].manager != address(0)) revert AlreadyConfigured();
        if (msg.sender != manager) revert NotManager();
        if (manager == address(0) || endTime <= startTime) revert BadConfig();
        _launches[id] = LaunchInfo({manager: manager, startTime: startTime, endTime: endTime, settled: false});
        emit LaunchConfigured(id, manager, startTime, endTime);
    }

    /// @notice Flip the pool to settled, opening it for trading. Only the pool's manager may call.
    function markSettled(PoolId id) external {
        LaunchInfo storage info = _launches[id];
        if (info.manager == address(0)) revert NotConfigured();
        if (msg.sender != info.manager) revert NotManager();
        if (info.settled) revert AlreadySettled();
        info.settled = true;
        emit Settled(id);
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal view override returns (bytes4) {
        if (_launches[key.toId()].manager == address(0)) revert NotConfigured();
        return BaseHook.beforeInitialize.selector;
    }

    /// @dev Block all swaps until the auction has cleared; afterwards the pool trades normally.
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (!_launches[key.toId()].settled) revert SwapsLockedUntilSettled();
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @dev Pre-settlement, only the manager may add liquidity (seeding the launch pool at the clearing
    /// price). The manager seeds via `poolManager.unlock`, so it is the `sender` of the modifyLiquidity
    /// call. Everyone else is locked out until settlement to prevent LP front-running. After settlement,
    /// anyone may provide liquidity.
    function _beforeAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        LaunchInfo storage info = _launches[key.toId()];
        if (!info.settled && sender != info.manager) revert AddLiquidityLockedUntilSettled();
        return BaseHook.beforeAddLiquidity.selector;
    }

    // --- views ---------------------------------------------------------------

    function launchInfo(PoolId id) external view returns (LaunchInfo memory) {
        return _launches[id];
    }

    function isSettled(PoolId id) external view returns (bool) {
        return _launches[id].settled;
    }
}
