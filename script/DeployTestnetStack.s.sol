// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Liftoff} from "../src/Liftoff.sol";
import {LiftoffRouter} from "../src/LiftoffRouter.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";

/// @notice Deploys a full Liftoff stack to X Layer TESTNET (chainId 1952), where Uniswap v4 is not
/// officially deployed — so we deploy our own PoolManager (v4-core is permissionless), then the hook
/// and factory against it. Free via the faucet: https://web3.okx.com/xlayer/faucet
///
/// Run:
///   forge script script/DeployTestnetStack.s.sol:DeployTestnetStack \
///     --rpc-url https://testrpc.xlayer.tech/terigon --private-key $PRIVATE_KEY --broadcast
contract DeployTestnetStack is Script {
    function run() external {
        require(block.chainid == 1952, "wrong chain: expected X Layer testnet 1952");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        vm.startBroadcast(pk);

        PoolManager poolManager = new PoolManager(deployer);
        LiftoffRouter router = new LiftoffRouter(IPoolManager(address(poolManager)));

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(Liftoff).creationCode,
            abi.encode(IPoolManager(address(poolManager)), address(router))
        );
        Liftoff hook = new Liftoff{salt: salt}(IPoolManager(address(poolManager)), address(router));
        require(address(hook) == hookAddress, "DeployTestnetStack: hook address mismatch");

        LaunchFactory factory = new LaunchFactory(IPoolManager(address(poolManager)), hook);

        vm.stopBroadcast();

        console.log("X Layer testnet (1952) deploy:");
        console.log("  PoolManager  :", address(poolManager));
        console.log("  LiftoffRouter:", address(router));
        console.log("  Liftoff hook :", address(hook));
        console.log("  LaunchFactory:", address(factory));
    }
}
