// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {SealedLaunchHook} from "../src/SealedLaunchHook.sol";
import {CommitRevealLaunch} from "../src/CommitRevealLaunch.sol";

/// @notice Phase 1 of the v2 Commit-Reveal Sealed Launch mainnet demo (X Layer 196). Reuses the
/// existing SealedLaunchHook (it gates *per pool*; each new LaunchToken gives a fresh poolId).
/// Deploys CommitRevealLaunch + a fresh dUSD2 quote token, funds two on-chain bidders, opens a
/// real launch with a short commit + reveal window, and posts both commitments.
///
/// Run:
///   PRIVATE_KEY=0x.. BIDDER2_PRIVATE_KEY=0x.. forge script \
///     script/DeployCommitRevealDemo.s.sol:DeployCommitRevealDemo \
///     --rpc-url https://rpc.xlayer.tech --broadcast
contract DeployCommitRevealDemo is Script {
    address constant XLAYER_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
    address constant EXISTING_HOOK = 0x594B539591e51e7981b05126B7e4d869C3BaA880;

    int24 constant DEMO_TICK_SPACING = 60;

    // Sealed bid sizes: bidders escrow masked > revealed, real amount stays hidden until reveal.
    uint256 constant MASKED_A = 1_000e18;
    uint256 constant MASKED_B = 500e18;
    uint256 constant AMOUNT_A = 700e18;
    uint256 constant AMOUNT_B = 300e18;

    function _saltA() internal pure returns (bytes32) { return keccak256("v2-demo-saltA"); }
    function _saltB() internal pure returns (bytes32) { return keccak256("v2-demo-saltB"); }

    function run() external {
        require(block.chainid == 196, "wrong chain: expected X Layer mainnet 196");
        uint256 pkA = vm.envUint("PRIVATE_KEY");
        uint256 pkB = vm.envUint("BIDDER2_PRIVATE_KEY");
        SealedLaunchHook hook = SealedLaunchHook(EXISTING_HOOK);

        (address launchAddr, address quoteAddr, address tokenAddr, PoolId id, uint64 cEnd, uint64 rEnd) =
            _deployAndOpen(pkA, pkB, hook);

        _commitB(pkB, launchAddr, quoteAddr, id);

        _report(launchAddr, address(hook), quoteAddr, tokenAddr, vm.addr(pkA), vm.addr(pkB), cEnd, rEnd, id);
    }

    function _deployAndOpen(uint256 pkA, uint256 pkB, SealedLaunchHook hook)
        internal
        returns (address launchAddr, address quoteAddr, address tokenAddr, PoolId id, uint64 cEnd, uint64 rEnd)
    {
        address bidderA = vm.addr(pkA);
        address bidderB = vm.addr(pkB);
        IPoolManager pmgr = IPoolManager(XLAYER_POOL_MANAGER);
        uint64 commitWindow = uint64(vm.envOr("COMMIT_WINDOW", uint256(90)));
        uint64 revealWindow = uint64(vm.envOr("REVEAL_WINDOW", uint256(90)));

        vm.startBroadcast(pkA);

        CommitRevealLaunch launch = new CommitRevealLaunch(pmgr, hook);
        MockERC20 quote = new MockERC20("CR Demo USD", "dUSD2", 18);
        quote.mint(bidderA, MASKED_A);
        quote.mint(bidderB, MASKED_B);

        // Fund bidder B for gas on X Layer (~5x what their 2 txs need).
        (bool ok,) = bidderB.call{value: 0.001 ether}("");
        require(ok, "bidderB gas transfer failed");

        uint64 start = uint64(block.timestamp);
        cEnd = start + commitWindow;
        rEnd = cEnd + revealWindow;

        (tokenAddr, id) = _open(launch, address(quote), start, cEnd, rEnd);
        _commitA(launch, address(quote), id, bidderA);

        vm.stopBroadcast();

        launchAddr = address(launch);
        quoteAddr = address(quote);
    }

    function _open(CommitRevealLaunch launch, address quote, uint64 start, uint64 cEnd, uint64 rEnd)
        internal
        returns (address tokenAddr, PoolId id)
    {
        PoolKey memory key;
        (tokenAddr, key, id) = launch.createLaunch(
            CommitRevealLaunch.LaunchParams({
                name: "Sealed Bid Demo",
                symbol: "SBID",
                totalSupply: 1_000_000e18,
                offeredTokens: 400_000e18,
                lpTokens: 300_000e18,
                quote: Currency.wrap(quote),
                startTime: start,
                commitEnd: cEnd,
                revealEnd: rEnd,
                minRaise: 0,
                maxMaskedPerWallet: 0,
                tickSpacing: DEMO_TICK_SPACING
            })
        );
        key;
    }

    function _commitA(CommitRevealLaunch launch, address quote, PoolId id, address bidderA) internal {
        bytes32 commitA = launch.commitmentFor(AMOUNT_A, _saltA(), bidderA);
        IERC20(quote).approve(address(launch), type(uint256).max);
        launch.commit(id, commitA, MASKED_A);
    }

    function _commitB(uint256 pkB, address launchAddr, address quoteAddr, PoolId id) internal {
        address bidderB = vm.addr(pkB);
        CommitRevealLaunch launch = CommitRevealLaunch(launchAddr);
        bytes32 commitB = launch.commitmentFor(AMOUNT_B, _saltB(), bidderB);
        vm.startBroadcast(pkB);
        IERC20(quoteAddr).approve(launchAddr, type(uint256).max);
        launch.commit(id, commitB, MASKED_B);
        vm.stopBroadcast();
    }

    function _report(
        address launchAddr,
        address hookAddr,
        address quoteAddr,
        address tokenAddr,
        address bidderA,
        address bidderB,
        uint64 cEnd,
        uint64 rEnd,
        PoolId id
    ) internal pure {
        console.log("=== Commit-Reveal Launch v2 (X Layer 196) - Phase 1 ===");
        console.log("CommitRevealLaunch:", launchAddr);
        console.log("Hook (reused)     :", hookAddr);
        console.log("Quote (dUSD2)     :", quoteAddr);
        console.log("Demo token (SBID) :", tokenAddr);
        console.log("Bidder A          :", bidderA);
        console.log("Bidder B          :", bidderB);
        console.log("commitEnd ts      :", cEnd);
        console.log("revealEnd ts      :", rEnd);
        console.log("poolId:");
        console.logBytes32(PoolId.unwrap(id));
    }
}
