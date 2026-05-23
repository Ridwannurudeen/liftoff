// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BaseTest} from "./utils/BaseTest.sol";
import {Liftoff} from "../src/Liftoff.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";

contract LaunchFactoryTest is BaseTest {
    using PoolIdLibrary for PoolKey;

    Liftoff hook;
    LaunchFactory factory;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapTest;
    MockERC20 quote;

    address token;
    PoolKey key;
    PoolId id;
    bool tokenIsC0;

    function setUp() public {
        deployArtifactsAndLabel();
        lpRouter = new PoolModifyLiquidityTest(poolManager);
        swapTest = new PoolSwapTest(poolManager);

        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x7777 << 144)
        );
        deployCodeTo("Liftoff.sol:Liftoff", abi.encode(poolManager, address(0)), flags);
        hook = Liftoff(flags);

        factory = new LaunchFactory(poolManager, hook);

        quote = new MockERC20("Quote", "Q", 18);
        quote.mint(address(this), 1e30);

        (token, key, id) = factory.launch(
            LaunchFactory.LaunchParams({
                name: "Demo",
                symbol: "DEMO",
                supply: 1e27,
                quote: Currency.wrap(address(quote)),
                sqrtPriceX96: Constants.SQRT_PRICE_1_1,
                startFee: 500_000,
                endFee: 3_000,
                baselineFee: 3_000,
                launchWindow: 1 hours,
                maxBuyPerTx: 0,
                maxBuyPerWallet: 0,
                graduationVolume: 1e18,
                lpLockUntil: uint64(block.timestamp + 1 days),
                maxSellPerTx: 0,
                maxSellPerWallet: 0,
                maxSellBpsOfReserve: 0
            })
        );
        tokenIsC0 = Currency.unwrap(key.currency0) == token;

        IERC20(token).approve(address(lpRouter), type(uint256).max);
        IERC20(address(quote)).approve(address(lpRouter), type(uint256).max);
        IERC20(token).approve(address(swapTest), type(uint256).max);
        IERC20(address(quote)).approve(address(swapTest), type(uint256).max);

        lpRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: int256(1e21),
                salt: bytes32(0)
            }),
            Constants.ZERO_BYTES
        );
    }

    function _buy(uint256 amtIn) internal {
        bool zeroForOne = !tokenIsC0;
        swapTest.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amtIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            Constants.ZERO_BYTES
        );
    }

    function test_launch_configuresAndInitializes() public view {
        assertTrue(token.code.length > 0);
        (bool configured,,,,) = hook.states(id);
        assertTrue(configured);
        assertEq(hook.currentBuyFee(id), 500_000);
    }

    function test_launch_swapAndGraduate() public {
        _buy(1e16);
        (,,,, uint256 vol) = hook.states(id);
        assertGt(vol, 0);

        vm.warp(block.timestamp + 1 hours + 1);
        _buy(1e18);
        (, bool graduated,,,) = hook.states(id);
        assertTrue(graduated);
        assertEq(hook.currentBuyFee(id), 3_000);
    }
}
