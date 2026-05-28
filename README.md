# Sealed Launch — an order-independent fair-launch hook for Uniswap v4 on X Layer

**A token launches through a sealed, uniform-price batch auction running entirely inside a Uniswap v4 hook.** During the launch window the pool can't be swapped; buyers commit quote tokens; at window close everyone clears at **one uniform price**, pro-rata. Being first — or paying to be first — buys you *nothing*. Then the pool opens for normal trading, seeded with liquidity at the clearing price.

Built for the OKX **Build X "Hook the Future"** hackathon, deployed against the **official Uniswap v4 PoolManager on X Layer mainnet** (`0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`).

**Live:**
- https://liftoff.gudman.xyz — the pitch + read-only auction state widget (no wallet, no backend).
- https://liftoff.gudman.xyz/app — interactive launch lifecycle dApp: connect a wallet, paste any v2 launch + poolId (defaults to the mainnet demo), commit / reveal / settle / claim.

## Why this, and why X Layer specifically

In December 2025 X Layer migrated to the **OP Stack** and runs a **flashblocks** sequencer. We tested real mainnet blocks: transactions are **not** ordered by priority fee — block-level ordering is effectively unpredictable. That breaks the two fashionable anti-MEV designs:

- **Priority-fee "MEV-tax" hooks** (Angstrom-style) need descending-priority-fee ordering — which X Layer doesn't provide.
- **Oracle / LVR-aware AMMs** need a price feed — and no general-purpose price oracle is confirmed live on X Layer.

So instead of fighting ordering, **Sealed Launch makes ordering irrelevant.** A uniform-price batch auction is fair *by construction*: the clearing price and your allocation depend only on the ratio of your commitment to the total — never on which block, which position, or how much gas you paid. On a chain where you can't predict ordering, that's the only launch that is provably un-snipeable.

Existing launch hooks (Flaunch, Doppler) compete on fee-decay and Dutch auctions; MEV-capture hooks (Angstrom) route value to LPs and aren't built for launches. A **sealed uniform-price batch auction as a v4 launch hook** is proposed in research but, to our knowledge, has not been shipped. flap.sh — a launchpad and a co-initiator of this hackathon — has no anti-snipe today; Sealed Launch is directly adoptable as its fair-launch mode.

## How it maps to the judging criteria

- **Innovation** — order-independent, uniform-price sealed batch auction implemented as a v4 hook; fairness is a property of the mechanism, not a parameter. Verified white space.
- **Market Potential** — every token launch needs anti-snipe; this is adoptable by X Layer's launchpads (flap.sh) and grows v4 pools, liquidity, real users and OKB gas on a chain whose v4 TVL is still tiny.
- **Completion** — 62/62 Foundry tests (incl. a live X Layer mainnet fork) **and a real auction settled on mainnet**: deploy → commit → settle at one price → seed LP → trade. All inspectable on OKLink.

## Architecture

Two contracts plus the launched token:

- **`src/SealedLaunchHook.sol`** — the gating hook (`BaseHook`, permissions `beforeInitialize | beforeAddLiquidity | beforeSwap`). It holds no funds and runs no price math; it is purely the access-control gate around the pool:
  - `_beforeSwap` reverts until the auction is `settled` — nobody trades the token before it clears.
  - `_beforeAddLiquidity` reverts pre-settlement unless the caller is the launch manager — nobody front-runs the LP.
  - `markSettled` (manager-only) opens the pool.
- **`src/SealedLaunch.sol`** — factory + escrow + settlement (`IUnlockCallback`):
  - `createLaunch` deploys the token, builds + configures the pool (not initialized yet — the pool is initialized *at* the clearing price), opens commitments.
  - `commit(poolId, amount)` escrows quote. Order and block position are irrelevant.
  - `settle(poolId)` computes the uniform clearing price `P = totalCommitted / offeredTokens`, initializes the pool at `P`, seeds full-range liquidity through `poolManager.unlock` → `modifyLiquidity`, opens trading, and forwards the raise to the launcher. If `totalCommitted < minRaise` the launch fails and commitments are refundable.
  - `claim(poolId)` sends each buyer `offeredTokens · committed / totalCommitted`; `refund` returns funds on a failed launch.

```
LaunchParams {
  string name; string symbol; uint256 totalSupply;
  uint256 offeredTokens;  // sold to bidders, distributed pro-rata at the clearing price
  uint256 lpTokens;       // seeded into the pool at settlement
  Currency quote; uint64 startTime; uint64 endTime;
  uint256 minRaise;       // launch fails (refunds) if not met
  uint256 maxCommitPerWallet; int24 tickSpacing;
}
```

## Deployed on X Layer mainnet (chain 196)

| Contract | Address |
|---|---|
| SealedLaunchHook | `0x594B539591e51e7981b05126B7e4d869C3BaA880` |
| SealedLaunch (manager) | `0xd6a240183eea10cd74f9911FE3f7717c90564B8C` |
| SEAL (demo token) | `0x9A758af7A7EAB7B7F038caC7AA6127d232fC159B` |
| dUSD (demo quote) | `0x8FfBcEdbD23B128b2652a2a2786515DdEF131182` |

A real launch was run end-to-end on mainnet (commit → settle at uniform price → LP seeded → live swap). On-chain proof: `isSettled = true`, pool liquidity `> 0`. Tx provenance in `broadcast/DeploySealedLaunch.s.sol/196/` and `broadcast/SettleSealedLaunch.s.sol/196/`.

## Test

```bash
forge test                                       # full suite (62 tests)
forge test --match-contract SealedLaunchTest     # v1 sealed batch auction (23)
forge test --match-contract CommitRevealLaunch   # v2 commit-reveal sealed-bid (12)
```

The headline test, `test_sniperFirstBlockSamePricePerTokenAsLastBlock`, proves a first-block "sniper" and a last-block buyer get **identical allocation and identical price per token**.

## Deploy to X Layer

```bash
# Phase 1 — deploy hook + manager, open a launch, commit
PRIVATE_KEY=0x.. WINDOW=150 forge script script/DeploySealedLaunch.s.sol:DeploySealedLaunch \
  --rpc-url https://rpc.xlayer.tech --broadcast
# Phase 2 — after the window closes: settle at the uniform price, claim, trade
PRIVATE_KEY=0x.. LAUNCH=0x.. POOL_ID=0x.. forge script script/SettleSealedLaunch.s.sol:SettleSealedLaunch \
  --rpc-url https://rpc.xlayer.tech --broadcast
```

The hook address is CREATE2-mined (`HookMiner`) so its low bits carry the permission flags (`0x2880`). Gas is paid in **OKB**.

## v2 — Commit-Reveal sealed bids (live on X Layer mainnet, multi-bidder demo settled)

`src/CommitRevealLaunch.sol` extends v1 with a hashed commit + masked deposit: bidders post `keccak256(amount, salt, bidder)` and escrow an upper-bound deposit; they reveal the real amount during a reveal window, with the overage refunded. The same `SealedLaunchHook` gates the pool (reused across v1 and v2 pools). Bid sizes stay hidden on-chain until reveal, so the auction is now order-*independent* **and** size-sealed. 12 dedicated unit tests cover seal/reveal correctness, pro-rata on revealed bids, failed-launch refunds, and pool seeding at the clearing price.

**Deployed + demonstrated on X Layer mainnet (chain 196):**

| Contract | Address |
|---|---|
| CommitRevealLaunch (manager) | `0xaed6BD08CDBaD833312d6BcFd9F97954350F606e` |
| dUSD2 (demo quote) | `0x632bdC371EF86b9238dE795aEE2babABE3A5A277` |
| SBID (demo token) | `0xe39a3D775690C419f07A029d2423c74a74b86952` |

Two on-chain bidders, asymmetric sealed bids: A masked 1000 dUSD2 / revealed 700, B masked 500 / revealed 300. Pro-rata claims (28:12 = 7:3) confirmed: A=280,000 SBID, B=120,000 SBID. Full lifecycle ran end-to-end on mainnet — both commits → both reveals (overages refunded) → settle at uniform clearing price → both claim → live post-settlement swap. Tx provenance in `broadcast/DeployCommitRevealDemo.s.sol/196/`, `broadcast/RevealCommitRevealDemo.s.sol/196/`, `broadcast/SettleCommitRevealDemo.s.sol/196/`.

## Honest scope notes

- v1 (live) is a **proportional uniform-price** batch (allocation = `offeredTokens · committed / totalCommitted`). It is order-independent and un-snipeable; v2 (`CommitRevealLaunch`) adds hashed-commit bid privacy on top of the same gating hook.
- v2 commit-reveal has a documented "free-option" trade-off: a committer can skip reveal if the clearing price turns unfavorable. Bond-burn / partial-forfeiture hardening is a future iteration.
- Hackathon-grade: a third-party audit is required before real TVL.

## v1 predecessor — Liftoff

This repo began as **Liftoff**, a fair-launch + fair-life hook (time-decaying launch fee, LP lock, graduation, anti-dump caps). It is fully implemented, tested, and **also deployed on X Layer mainnet** (hook `0xA03D3d9043324955a4ea2a1bE77352851611E2C0`), and is retained as the documented predecessor — see [`docs/`](docs/) and `src/Liftoff.sol`. Sealed Launch supersedes it: fee-decay anti-snipe is commoditized (Flaunch/Doppler), whereas order-independent batch clearing is novel and uniquely suited to X Layer's flashblock sequencer.
