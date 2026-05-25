// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {SealedLaunchHook} from "../src/SealedLaunchHook.sol";
import {SealedLaunch} from "../src/SealedLaunch.sol";

/// @notice Phase 1 of the MAINNET Sealed Launch demo on X Layer (chain 196), against the OFFICIAL
/// Uniswap v4 PoolManager. Deploys the gating hook (CREATE2-mined for the 0x2880 flag bits) + the
/// SealedLaunch manager + a demo quote token, opens a real launch with a short commit window, and
/// commits to it. After the window closes, run `SettleSealedLaunch` to clear the auction on-chain.
///
/// Run:
///   PRIVATE_KEY=0x.. WINDOW=120 forge script script/DeploySealedLaunch.s.sol:DeploySealedLaunch \
///     --rpc-url https://rpc.xlayer.tech --broadcast
contract DeploySealedLaunch is Script {
    address constant XLAYER_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        IPoolManager pmgr = IPoolManager(XLAYER_POOL_MANAGER);
        uint64 window = uint64(vm.envOr("WINDOW", uint256(120)));

        uint160 flags =
            uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);

        vm.startBroadcast(pk);

        (address hookAddr, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(SealedLaunchHook).creationCode, abi.encode(pmgr));
        SealedLaunchHook hook = new SealedLaunchHook{salt: salt}(pmgr);
        require(address(hook) == hookAddr, "hook addr mismatch");

        SealedLaunch launch = new SealedLaunch(pmgr, hook);

        MockERC20 quote = new MockERC20("Demo USD", "dUSD", 18);
        quote.mint(deployer, 1e24);

        uint64 start = uint64(block.timestamp);
        uint64 end = start + window;

        (address token, PoolKey memory key, PoolId id) = launch.createLaunch(
            SealedLaunch.LaunchParams({
                name: "Sealed Demo",
                symbol: "SEAL",
                totalSupply: 1_000_000e18,
                offeredTokens: 400_000e18,
                lpTokens: 300_000e18,
                quote: Currency.wrap(address(quote)),
                startTime: start,
                endTime: end,
                minRaise: 0,
                maxCommitPerWallet: 0,
                tickSpacing: 60
            })
        );

        // Commit 1,000 dUSD from the deployer (a real on-chain bid into the sealed auction).
        IERC20(address(quote)).approve(address(launch), type(uint256).max);
        launch.commit(id, 1_000e18);

        vm.stopBroadcast();

        console.log("=== Sealed Launch deploy (X Layer 196) - Phase 1 ===");
        console.log("SealedLaunchHook :", address(hook));
        console.log("SealedLaunch     :", address(launch));
        console.log("Quote (dUSD)     :", address(quote));
        console.log("Demo token SEAL  :", token);
        console.log("commit window end:", end);
        console.log("totalCommitted   :", launch.totalCommitted(id));
        console.log("poolId:");
        console.logBytes32(PoolId.unwrap(id));
    }
}
