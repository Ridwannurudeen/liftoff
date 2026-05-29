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

import {CommitRevealLaunch} from "../src/CommitRevealLaunch.sol";

/// @notice Phase 3 of the v2 demo: clear the auction at the uniform price on revealed bids,
/// both bidders claim their pro-rata allocation, then a small post-settlement swap proves the
/// pool opened for trading. Must run after revealEnd.
///
/// Run:
///   PRIVATE_KEY=0x.. BIDDER2_PRIVATE_KEY=0x.. LAUNCH=0x.. POOL_ID=0x.. \
///     forge script script/SettleCommitRevealDemo.s.sol:SettleCommitRevealDemo \
///     --rpc-url https://rpc.xlayer.tech --broadcast
contract SettleCommitRevealDemo is Script {
    using StateLibrary for IPoolManager;

    function run() external {
        require(block.chainid == 196, "wrong chain: expected X Layer mainnet 196");
        uint256 pkA = vm.envUint("PRIVATE_KEY");
        uint256 pkB = vm.envUint("BIDDER2_PRIVATE_KEY");
        CommitRevealLaunch launch = CommitRevealLaunch(vm.envAddress("LAUNCH"));
        require(address(launch).code.length > 0, "LAUNCH has no code: bad address?");
        PoolId id = PoolId.wrap(vm.envBytes32("POOL_ID"));
        require(PoolId.unwrap(id) != bytes32(0), "POOL_ID is zero");

        // Settle + claim A + small demo swap from bidder A's broadcast.
        vm.startBroadcast(pkA);
        launch.settle(id);
        launch.claim(id);
        if (!vm.envOr("SKIP_DEMO_SWAP", false)) {
            _demoSwap(launch, id);
        }
        vm.stopBroadcast();

        // Bidder B claims their pro-rata allocation.
        vm.startBroadcast(pkB);
        launch.claim(id);
        vm.stopBroadcast();

        _report(launch, id, vm.addr(pkA), vm.addr(pkB));
    }

    function _poolKey(CommitRevealLaunch launch, PoolId id) internal view returns (PoolKey memory) {
        CommitRevealLaunch.Launch memory l = launch.getLaunch(id);
        (Currency c0, Currency c1) =
            l.tokenIsCurrency0 ? (Currency.wrap(l.token), l.quote) : (l.quote, Currency.wrap(l.token));
        return PoolKey(c0, c1, launch.LP_FEE(), l.tickSpacing, IHooks(address(launch.hook())));
    }

    function _demoSwap(CommitRevealLaunch launch, PoolId id) internal {
        CommitRevealLaunch.Launch memory l = launch.getLaunch(id);
        PoolKey memory key = _poolKey(launch, id);
        PoolSwapTest swapRouter = new PoolSwapTest(launch.poolManager());
        IERC20(Currency.unwrap(l.quote)).approve(address(swapRouter), type(uint256).max);
        bool zeroForOne = !l.tokenIsCurrency0; // quote -> token
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(1e18),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            Constants.ZERO_BYTES
        );
    }

    function _report(CommitRevealLaunch launch, PoolId id, address a, address b) internal view {
        (uint160 sqrtPrice,,,) = launch.poolManager().getSlot0(id);
        CommitRevealLaunch.Launch memory l = launch.getLaunch(id);
        console.log("=== Commit-Reveal v2 - Phase 3 settle ===");
        console.log("settled?       :", launch.hook().isSettled(id));
        console.log("totalRevealed  :", l.totalRevealed);
        console.log("clearing sqrtP :", uint256(launch.clearingPrice(id)));
        console.log("pool sqrtPrice :", uint256(sqrtPrice));
        console.log("Bidder A token :", IERC20(l.token).balanceOf(a));
        console.log("Bidder B token :", IERC20(l.token).balanceOf(b));
    }
}
