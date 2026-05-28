// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {SealedLaunch} from "../src/SealedLaunch.sol";

/// @notice Phase 2 of the Sealed Launch demo: after the commit window closes, clear the auction at a
/// single uniform price on-chain, claim the pro-rata allocation, and execute a real swap to prove the
/// pool opened for trading at the clearing price.
///
/// Run (after the window from Phase 1 has elapsed):
///   PRIVATE_KEY=0x.. LAUNCH=0x.. POOL_ID=0x.. forge script script/SettleSealedLaunch.s.sol:SettleSealedLaunch \
///     --rpc-url https://rpc.xlayer.tech --broadcast
contract SettleSealedLaunch is Script {
    using StateLibrary for IPoolManager;

    function run() external {
        require(block.chainid == 196, "wrong chain: expected X Layer mainnet 196");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        SealedLaunch launch = SealedLaunch(vm.envAddress("LAUNCH"));
        PoolId id = PoolId.wrap(vm.envBytes32("POOL_ID"));

        vm.startBroadcast(pk);
        launch.settle(id);
        launch.claim(id);
        if (!vm.envOr("SKIP_DEMO_SWAP", false)) {
            _demoSwap(launch, id);
        }
        vm.stopBroadcast();

        _report(launch, id, vm.addr(pk));
    }

    function _poolKey(SealedLaunch launch, PoolId id) internal view returns (PoolKey memory) {
        SealedLaunch.Launch memory l = launch.getLaunch(id);
        (Currency c0, Currency c1) =
            l.tokenIsCurrency0 ? (Currency.wrap(l.token), l.quote) : (l.quote, Currency.wrap(l.token));
        return PoolKey(c0, c1, launch.LP_FEE(), l.tickSpacing, IHooks(address(launch.hook())));
    }

    /// @dev Buy the launched token with a small quote-in swap, proving the pool trades post-settlement.
    function _demoSwap(SealedLaunch launch, PoolId id) internal {
        SealedLaunch.Launch memory l = launch.getLaunch(id);
        PoolKey memory key = _poolKey(launch, id);
        PoolSwapTest swapRouter = new PoolSwapTest(launch.poolManager());
        IERC20(Currency.unwrap(l.quote)).approve(address(swapRouter), type(uint256).max);
        bool zeroForOne = !l.tokenIsCurrency0; // quote -> token
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(5e18),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            Constants.ZERO_BYTES
        );
    }

    function _report(SealedLaunch launch, PoolId id, address who) internal view {
        (uint160 sqrtPrice,,,) = launch.poolManager().getSlot0(id);
        console.log("=== Sealed Launch settle (X Layer 196) - Phase 2 ===");
        console.log("settled       :", launch.hook().isSettled(id));
        console.log("clearing sqrtP:", uint256(launch.clearingPrice(id)));
        console.log("pool sqrtPrice:", uint256(sqrtPrice));
        console.log("token claimed :", IERC20(launch.getLaunch(id).token).balanceOf(who));
    }
}
