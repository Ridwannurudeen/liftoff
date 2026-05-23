// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Liftoff} from "../src/Liftoff.sol";

/// @notice Deploys the Liftoff hook to X Layer against the official Uniswap v4 PoolManager.
/// Standalone (does not use the template's hookmate-based BaseScript, which lacks chainId 196).
///
/// Usage:
///   forge script script/DeployLiftoff.s.sol:DeployLiftoff --rpc-url https://rpc.xlayer.tech \
///     --private-key $PRIVATE_KEY --broadcast
contract DeployLiftoff is Script {
    // Official Uniswap v4 PoolManager on X Layer mainnet (chainId 196), bytecode-verified.
    address constant XLAYER_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    function run() external {
        IPoolManager poolManager = IPoolManager(vm.envOr("POOL_MANAGER", XLAYER_POOL_MANAGER));

        // Must match Liftoff.getHookPermissions() exactly, or deployment reverts.
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(Liftoff).creationCode, constructorArgs);

        vm.startBroadcast();
        Liftoff hook = new Liftoff{salt: salt}(poolManager);
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployLiftoff: hook address mismatch");
        console.log("PoolManager:", address(poolManager));
        console.log("Liftoff    :", address(hook));
    }
}
