// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BaseTest} from "./utils/BaseTest.sol";
import {Liftoff} from "../src/Liftoff.sol";

/// @notice Property/fuzz tests for the launch-fee curve.
contract LiftoffFuzzTest is BaseTest {
    using PoolIdLibrary for PoolKey;

    Liftoff hook;
    PoolKey key;
    PoolId id;

    uint64 constant WINDOW = 1 hours;
    uint24 constant START_FEE = 500_000;
    uint24 constant END_FEE = 3_000;
    uint256 launchStart;

    function setUp() public {
        deployArtifactsAndLabel();

        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x9999 << 144)
        );
        deployCodeTo("Liftoff.sol:Liftoff", abi.encode(poolManager), flags);
        hook = Liftoff(flags);

        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        (address t0, address t1) = address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));
        key = PoolKey(Currency.wrap(t0), Currency.wrap(t1), LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        id = key.toId();

        hook.configureLaunch(
            key,
            Liftoff.LaunchConfig({
                tokenIsCurrency0: true,
                startFee: START_FEE,
                endFee: END_FEE,
                baselineFee: END_FEE,
                launchWindow: WINDOW,
                maxBuyPerTx: 0,
                graduationVolume: 1e18,
                lpLockUntil: uint64(block.timestamp + 1 days),
                maxSellPerTx: 0
            })
        );
        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
        launchStart = block.timestamp;
    }

    function testFuzz_feeWithinBounds(uint64 warpBy) public {
        warpBy = uint64(bound(warpBy, 0, 100 hours));
        vm.warp(launchStart + warpBy);
        uint24 fee = hook.currentBuyFee(id);
        assertLe(fee, START_FEE);
        assertGe(fee, END_FEE);
    }

    function test_feeStrictlyDecreasesAcrossWindow() public {
        assertEq(hook.currentBuyFee(id), START_FEE);
        vm.warp(launchStart + WINDOW / 4);
        uint24 q1 = hook.currentBuyFee(id);
        vm.warp(launchStart + WINDOW / 2);
        uint24 q2 = hook.currentBuyFee(id);
        vm.warp(launchStart + (WINDOW * 3) / 4);
        uint24 q3 = hook.currentBuyFee(id);
        assertLt(q1, START_FEE);
        assertLt(q2, q1);
        assertLt(q3, q2);
        vm.warp(launchStart + WINDOW);
        assertEq(hook.currentBuyFee(id), END_FEE);
    }
}
