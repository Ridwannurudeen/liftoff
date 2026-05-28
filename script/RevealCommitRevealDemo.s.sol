// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {CommitRevealLaunch} from "../src/CommitRevealLaunch.sol";

/// @notice Phase 2 of the v2 demo: both bidders open their sealed bids during the reveal window.
/// Must run after commitEnd, before revealEnd.
///
/// Run:
///   PRIVATE_KEY=0x.. BIDDER2_PRIVATE_KEY=0x.. LAUNCH=0x.. POOL_ID=0x.. \
///     forge script script/RevealCommitRevealDemo.s.sol:RevealCommitRevealDemo \
///     --rpc-url https://rpc.xlayer.tech --broadcast
contract RevealCommitRevealDemo is Script {
    function run() external {
        uint256 pkA = vm.envUint("PRIVATE_KEY");
        uint256 pkB = vm.envUint("BIDDER2_PRIVATE_KEY");
        CommitRevealLaunch launch = CommitRevealLaunch(vm.envAddress("LAUNCH"));
        PoolId id = PoolId.wrap(vm.envBytes32("POOL_ID"));

        bytes32 saltA = keccak256("v2-demo-saltA");
        bytes32 saltB = keccak256("v2-demo-saltB");
        uint256 amountA = 700e18;
        uint256 amountB = 300e18;

        vm.startBroadcast(pkA);
        launch.reveal(id, amountA, saltA);
        vm.stopBroadcast();

        vm.startBroadcast(pkB);
        launch.reveal(id, amountB, saltB);
        vm.stopBroadcast();

        console.log("=== Commit-Reveal v2 - Phase 2 reveals ===");
        console.log("totalRevealed:", launch.totalRevealed(id));
        console.log("Bidder A revealed:", launch.getBid(id, vm.addr(pkA)).revealed);
        console.log("Bidder B revealed:", launch.getBid(id, vm.addr(pkB)).revealed);
    }
}
