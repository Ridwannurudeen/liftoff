// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
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
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Liftoff} from "../src/Liftoff.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";

/// @notice One-command MAINNET deploy + live demo on X Layer (chainId 196), against the OFFICIAL
/// Uniswap v4 PoolManager. Deploys hook + factory, launches a demo token, seeds liquidity, and runs
/// the lifecycle (high-fee launch buys -> graduation -> baseline trading) so judges can inspect real
/// on-chain activity on OKLink.
///
/// Run:
///   forge script script/DeployMainnetStack.s.sol:DeployMainnetStack \
///     --rpc-url https://rpc.xlayer.tech --private-key $PRIVATE_KEY --broadcast
contract DeployMainnetStack is Script {
    using PoolIdLibrary for PoolKey;

    address constant XLAYER_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    PoolSwapTest swapRouter;
    PoolKey key;
    bool tokenIsC0;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        IPoolManager pmgr = IPoolManager(XLAYER_POOL_MANAGER);

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        vm.startBroadcast(pk);

        (address hookAddr, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(Liftoff).creationCode, abi.encode(pmgr));
        Liftoff hook = new Liftoff{salt: salt}(pmgr);
        require(address(hook) == hookAddr, "hook addr mismatch");

        LaunchFactory factory = new LaunchFactory(pmgr, hook);
        PoolModifyLiquidityTest lpRouter = new PoolModifyLiquidityTest(pmgr);
        swapRouter = new PoolSwapTest(pmgr);

        MockERC20 quote = new MockERC20("Demo USD", "dUSD", 18);
        quote.mint(deployer, 1e24);

        address token;
        (token, key,) = factory.launch(
            LaunchFactory.LaunchParams({
                name: "Liftoff Demo",
                symbol: "LIFT",
                supply: 1e27,
                quote: Currency.wrap(address(quote)),
                sqrtPriceX96: Constants.SQRT_PRICE_1_1,
                startFee: 500_000, // 50% anti-snipe launch fee
                endFee: 3_000,
                baselineFee: 3_000,
                launchWindow: 1 hours,
                maxBuyPerTx: 0,
                graduationVolume: 2e18, // small so the demo graduates in-script (by volume)
                lpLockUntil: uint64(block.timestamp + 30 days),
                maxSellPerTx: 0
            })
        );
        tokenIsC0 = Currency.unwrap(key.currency0) == token;

        IERC20(token).approve(address(lpRouter), type(uint256).max);
        IERC20(address(quote)).approve(address(lpRouter), type(uint256).max);
        IERC20(token).approve(address(swapRouter), type(uint256).max);
        IERC20(address(quote)).approve(address(swapRouter), type(uint256).max);

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

        // Launch-phase buys at the high anti-snipe fee, accumulating volume to graduation.
        _buy(1e18);
        _buy(1e18);
        _buy(1e18);

        // Post-graduation trading at the baseline fee.
        _buy(1e17);
        _sell(1e17);

        vm.stopBroadcast();

        PoolId id = key.toId();
        (, bool graduated,,, uint256 vol) = hook.states(id);
        console.log("=== Liftoff mainnet deploy (X Layer 196) ===");
        console.log("Liftoff hook :", address(hook));
        console.log("LaunchFactory:", address(factory));
        console.log("Demo token   :", token);
        console.log("graduated    :", graduated);
        console.log("cum. volume  :", vol);
        console.log("current fee  :", uint256(hook.currentBuyFee(id)));
    }

    function _buy(uint256 amtIn) internal {
        bool zeroForOne = !tokenIsC0;
        swapRouter.swap(
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

    function _sell(uint256 amtIn) internal {
        bool zeroForOne = tokenIsC0;
        swapRouter.swap(
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
}
