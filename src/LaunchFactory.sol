// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {Liftoff} from "./Liftoff.sol";
import {LaunchToken} from "./LaunchToken.sol";

/// @title LaunchFactory
/// @notice One transaction to start a fair launch: deploy a fixed-supply token, create its
/// dynamic-fee v4 pool wired to the Liftoff hook, configure the launch terms, and initialize
/// the pool. The full token supply is minted to the launcher, who then seeds liquidity.
contract LaunchFactory {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;
    Liftoff public immutable hook;
    int24 public constant TICK_SPACING = 60;

    struct LaunchParams {
        string name;
        string symbol;
        uint256 supply;
        Currency quote; // the paired quote currency (e.g. USDC/OKB-wrapped)
        uint160 sqrtPriceX96; // initial price
        uint24 startFee;
        uint24 endFee;
        uint24 baselineFee;
        uint64 launchWindow;
        uint256 maxBuyPerTx;
        uint256 maxBuyPerWallet;
        uint256 graduationVolume;
        uint64 lpLockUntil;
        uint256 maxSellPerTx;
        uint256 maxSellPerWallet;
        uint16 maxSellBpsOfReserve;
    }

    event Launched(address indexed token, PoolId indexed poolId, address indexed launcher);

    constructor(IPoolManager _poolManager, Liftoff _hook) {
        poolManager = _poolManager;
        hook = _hook;
    }

    function launch(LaunchParams calldata p) external returns (address token, PoolKey memory key, PoolId id) {
        token = address(new LaunchToken(p.name, p.symbol, p.supply, msg.sender));

        bool tokenIsCurrency0 = token < Currency.unwrap(p.quote);
        (Currency c0, Currency c1) =
            tokenIsCurrency0 ? (Currency.wrap(token), p.quote) : (p.quote, Currency.wrap(token));

        key = PoolKey(c0, c1, LPFeeLibrary.DYNAMIC_FEE_FLAG, TICK_SPACING, IHooks(address(hook)));
        id = key.toId();

        hook.configureLaunch(
            key,
            Liftoff.LaunchConfig({
                tokenIsCurrency0: tokenIsCurrency0,
                startFee: p.startFee,
                endFee: p.endFee,
                baselineFee: p.baselineFee,
                launchWindow: p.launchWindow,
                maxBuyPerTx: p.maxBuyPerTx,
                maxBuyPerWallet: p.maxBuyPerWallet,
                graduationVolume: p.graduationVolume,
                lpLockUntil: p.lpLockUntil,
                maxSellPerTx: p.maxSellPerTx,
                maxSellPerWallet: p.maxSellPerWallet,
                maxSellBpsOfReserve: p.maxSellBpsOfReserve
            })
        );

        poolManager.initialize(key, p.sqrtPriceX96);
        emit Launched(token, id, msg.sender);
    }
}
