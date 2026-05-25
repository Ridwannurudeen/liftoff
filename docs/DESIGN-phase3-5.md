# Liftoff — Phase 3–5 Technical Design

This document specifies the post-hackathon roadmap (`ROADMAP.md` phases 3–5) at the level of
contract changes, mapped onto the **live** Liftoff architecture:

- `Liftoff` hook (`src/Liftoff.sol`) — `configureLaunch` / `states` / `configs`, caps enforced in
  `_afterSwap` on the realized `BalanceDelta`, dynamic fee via `_decayingFee` + `OVERRIDE_FEE_FLAG`.
- `LiftoffRouter` (`src/LiftoffRouter.sol`) — carries the end user in `hookData` for per-wallet caps.
- `LaunchFactory` (`src/LaunchFactory.sol`) — one-tx launch (token → dynamic-fee pool → configure → init).
- Deployed on X Layer mainnet (chain 196): hook `0xA03D3d9043324955a4ea2a1bE77352851611E2C0`,
  router `0x834bad8990a4a363A4468723fe74f2468f6aECE1`, factory `0x52bFAB995e1f6e8C875Be9d95aBa29bc15f756D5`.

**Prerequisites (Phase 2 leftovers, must precede Phase 3):** `liftoff-sdk` (TypeScript), creator/
protocol fee routing, and a third-party audit. Phase 3 adoption depends on the SDK; nothing below
should ship to real TVL pre-audit.

Legend: 🟢 buildable now · 🟡 buildable, depends on a prerequisite · 🔴 external (partnership/BD).

---

## Phase 3 — Become the X Layer launch standard

### 3.1 Fairness reputation 🟢
A creator's track record, computed from **on-chain launch outcomes** rather than self-reporting.

- **New contract `LiftoffReputation`.** Records one outcome per launched pool, keyed by creator
  (the `configurer` from the `LaunchConfigured` event / `msg.sender` of `configureLaunch`).
- **Inputs (all already on-chain):** did the pool **graduate** (`Graduated` event)? was the **LP
  lock honored** to `lpLockUntil`? were caps ever tripped (count of `*CapExceeded` reverts is not
  on-chain, but cap *config strength* is, from `configs(poolId)`)? time-to-graduation; post-grad
  survival (liquidity still present after N days via `StateLibrary.getLiquidity`).
- **Score:** a pure function `fairnessScore(creator) → uint16 (0–10000)` over {graduated share,
  lock-honored share, cap coverage, longevity}. Deterministic and recomputable off-chain for audit.
- **Standard reuse:** publish scores through an **ERC-8004-style reputation registry** so other
  apps consume creator reputation with existing tooling, instead of a Liftoff-only oracle.
- **Surface:** add a "fairness" panel to the site (`site/`) reading `fairnessScore` per creator;
  expose via the SDK.
- **Risk:** gameable by wash-launching many clean tiny pools — weight by liquidity/volume and decay
  old launches; treat the score as advisory, never as a gate on trading.

### 3.2 Launchpad-as-a-service 🟡 (needs `liftoff-sdk`)
Let other apps embed Liftoff launches.
- SDK exposes `createLaunch(params)` wrapping `LaunchFactory.launch`, plus typed readers for
  `configs`/`states`/`currentBuyFee` (selectors already used by `site/app.js`:
  `states` `0xfbdc1ef1`, `currentBuyFee` `0x594ab782`).
- Optional small protocol fee on launches via the Phase-2 fee-routing module (not a swap tax).

### 3.3 Adoption: flap.sh partnership & OKX integration 🔴 (external)
Not codeable by us — tracked here for completeness.
- **flap.sh:** offer Liftoff as flap's v4-native launch mode, replacing curve→migration. The wedge
  is that flap currently has no anti-snipe; integration is via the SDK from 3.2.
- **OKX:** OnchainOS skill, DEX-aggregator listing (aggregators should prefer **graduated** pools —
  `phaseOf`), OKB-denominated fees. Requires OKX-side review/listing.

---

## Phase 4 — Advanced mechanics + multi-chain

### 4.1 Dutch-auction launch curve 🟢
Generalize the fee schedule. Today `_decayingFee` is **linear** from `startFee`→`endFee` over
`launchWindow`. Add a `curve` enum to `LaunchConfig` (`Linear` | `Exponential` | `Step`) and switch
in `_decayingFee`. Keeps the existing storage layout additive; default `Linear` preserves behavior.
- **Risk:** must stay monotonic non-increasing (the standard requires it and a fuzz test asserts it).

### 4.2 Sniper-value-recapture (SVR) 🟢, higher complexity
Redistribute the elevated launch fee to genuine early buyers rather than to LPs.
- During `Launching`, the buy-fee premium above `baselineFee` is accrued (not paid to the LP
  position) and escrowed; at graduation it is claimable pro-rata by wallets that bought during the
  window (using the existing per-wallet `boughtBy[poolId][user]` accounting).
- **Mechanism:** requires `afterSwapReturnDelta` (currently `false` in `getHookPermissions`) to take
  a portion of the swap delta into the hook. This is the most invasive change — needs careful delta
  accounting and its own audit pass.

### 4.3 Vesting positions as NFTs 🟢
Wrap early-buyer / creator allocations as ERC-721 positions that unlock on a schedule, enforced by
the same `beforeRemoveLiquidity`/sell-cap machinery keyed to an NFT instead of a wallet.

### 4.4 Volatility-aware anti-dump 🟢
Make `maxSellBpsOfReserve` adaptive: widen caps in calm markets, tighten on sharp drawdowns. Read
short-window price from the pool (`StateLibrary.getSlot0`) in `_enforceSellCaps`; keep a hard floor/
ceiling so it can't be gamed to either extreme.

### 4.5 Multi-chain rollout 🟢
Deploy the same hook on every chain with official Uniswap v4.
- Parametrize `DeployMainnetStack` over a `{chainId → PoolManager}` table (today X Layer
  `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` is hardcoded). Mine the hook salt per chain
  (`HookMiner`).
- Candidates: Base, Arbitrum, Unichain, Ink — same code, larger TAM. **Gated on gas funding per
  chain;** no contract changes beyond the address table.

---

## Phase 5 — Moonshot

- **Standardize.** Promote the launch-covenant interface to a real ERC — draft in
  [`ERC-launch-covenants.md`](./ERC-launch-covenants.md). Align Liftoff's public names
  (`configureLaunch`→`configureCovenant`, `states`→`phaseOf`) to the interface in a non-breaking
  adapter so existing deployments keep working.
- **The fairness rail.** With the standard + reputation (3.1) + SDK (3.2), any launchpad can route
  launches through conforming covenants; consumers read one interface everywhere.
- **Governance/token (optional).** Only if there is real protocol-fee flow to steward; not before.

---

## Build sequencing

1. **Audit + `liftoff-sdk` + fee routing** (Phase 2 leftovers) — unblock everything below.
2. **Fairness reputation (3.1)** + **Dutch-auction curve (4.1)** — additive, low-risk, demoable.
3. **Multi-chain (4.5)** — config-only, scales reach.
4. **SVR (4.2)** / **vesting NFTs (4.3)** / **volatility caps (4.4)** — each its own audit pass.
5. **ERC submission (Phase 5)** once the interface is exercised by ≥2 implementations.

## Honest risks
- Every Phase-4 contract feature is **net-new unaudited code**; none should touch real TVL before audit.
- Reputation is advisory and gameable; never gate trading on it.
- Adoption (flap, OKX) is **earned, not assumed** — the standard lowers integration cost but doesn't guarantee it.
- Terms are immutable post-init by design: a covenant bug can't be patched on a live pool.
