// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";

/// @title LiftoffRouter
/// @notice Minimal v4 swap router that forwards the end user's address to the Liftoff hook in `hookData`,
/// so the hook can enforce per-wallet caps reliably (instead of falling back to `tx.origin`).
/// The user approves this router for the input currency; the router pulls input and forwards output to the user.
contract LiftoffRouter is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencySettler for Currency;

    IPoolManager public immutable poolManager;

    error NotPoolManager();

    struct CallbackData {
        address user;
        PoolKey key;
        SwapParams params;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Swap on `key`, identifying `msg.sender` as the end user to the hook.
    function swap(PoolKey calldata key, SwapParams calldata params) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            poolManager.unlock(abi.encode(CallbackData({user: msg.sender, key: key, params: params}))), (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        CallbackData memory data = abi.decode(raw, (CallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, abi.encode(data.user));

        int256 d0 = int256(delta.amount0());
        int256 d1 = int256(delta.amount1());
        if (d0 < 0) data.key.currency0.settle(poolManager, data.user, uint256(-d0), false);
        if (d1 < 0) data.key.currency1.settle(poolManager, data.user, uint256(-d1), false);
        if (d0 > 0) data.key.currency0.take(poolManager, data.user, uint256(d0), false);
        if (d1 > 0) data.key.currency1.take(poolManager, data.user, uint256(d1), false);

        return abi.encode(delta);
    }
}
