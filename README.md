# Sealed Launch

**A sealed batch-auction launch hook for Uniswap v4 on X Layer.** Live on mainnet against the official v4 PoolManager (chain 196).

Token launches get sniped. Every existing defense — fee decay, Dutch auctions, fixed-price windows, priority-fee MEV taxes — still rewards whoever orders first or pays the most to be ordered first. Sealed Launch doesn't fight ordering. It makes ordering irrelevant: bids are sealed during the window, everyone clears at one uniform price, allocation is pro-rata to what you committed.

> **Order doesn't matter. One uniform price.** Being first — or paying to be first — buys you nothing, because there is no front.

## Quick links

| | |
|---|---|
| Live site | https://sealedlaunch.gudman.xyz/ |
| Interactive dApp | https://sealedlaunch.gudman.xyz/app |
| Create a launch | https://sealedlaunch.gudman.xyz/app/create |
| X (Twitter) | https://x.com/sealedlaunch |
| GitHub | https://github.com/Ridwannurudeen/liftoff |

> The repo is named `liftoff` for historical reasons — Sealed Launch evolved from a prior fair-launch hook in this same repo. The project name is **Sealed Launch**.

## The problem

Whoever orders the trade first walks away with the cheap supply; retail eats the markup. That's the default for every token launch today.

- **Fee decay** — high opening fee that drops over time. The fastest wallet still wins; it just pays a tax to do it.
- **Dutch auctions** — price falls from a ceiling. First acceptable bid clears. Block ordering decides who.
- **Fixed-price windows** — first wallet to commit wins the allocation. Pure speed competition.
- **Priority-fee MEV taxes** — require descending-priority-fee block ordering. X Layer doesn't provide that.

In December 2025 X Layer migrated to the OP Stack and runs a **flashblocks** sequencer. We tested real mainnet blocks: transactions are not ordered by priority fee, and block-level ordering is effectively unpredictable. On a chain where you can't predict ordering, a sealed uniform-price batch auction is the only launch that's provably un-snipeable.

## How it works

Four phases. One price. Everyone clears the same.

1. **Commit.** Bidders post a hashed commitment `keccak256(amount, salt, bidder)` and escrow a masked deposit (an upper bound on the real bid). The pool is gated by `SealedLaunchHook`; nobody can trade the token.
2. **Reveal.** Bidders open their bid by submitting the real `amount + salt`. The overage is refunded atomically. Bid sizes appear on-chain only here.
3. **Settle.** Anyone calls `settle()`. The auction clears at one uniform price, the pool is initialized at that price, full-range LP is seeded via `poolManager.unlock → modifyLiquidity`, and trading opens. If `totalRevealed < minRaise`, the launch fails and every committer can reclaim.
4. **Claim.** Each revealer claims their pro-rata token allocation. Non-revealers reclaim their masked deposit.

```
clearingPrice P = totalRevealed / offeredTokens
allocation(b) = offeredTokens * revealed(b) / totalRevealed
```

Fairness is a property of the mechanism, not a tunable parameter.

## v1 vs v2

Two managers, one shared gating hook.

| | v1 — SealedLaunch | v2 — CommitRevealLaunch |
|---|---|---|
| Order-independent | yes | yes |
| Bid sizes sealed on-chain | no | yes (hashed commit + masked deposit) |
| Settlement | uniform price, pro-rata | uniform price, pro-rata |
| Mechanism | direct commit | hashed commit + reveal |
| Deployed on X Layer mainnet | yes | yes |

v2 supersedes v1 for new launches. v1 stays live as historical proof of the first end-to-end mainnet settlement.

**Honest scope notes:**

- v1 is a *proportional uniform-price* batch: `allocation = offeredTokens * committed / totalCommitted`. Order-independent and un-snipeable, but commitment amounts are visible on-chain during the window.
- v2 adds hashed-commit bid privacy on top of the same gating hook. Bid sizes only appear on-chain at reveal.
- v2 has a documented "free-option" trade-off: a committer can skip reveal if the clearing price turns unfavorable. Bond-burn / partial-forfeiture hardening is a future iteration.
- Hackathon-grade: a third-party audit is required before real TVL — see the disclosed-findings section below.

## Architecture

- **`src/SealedLaunchHook.sol`** — v4 `BaseHook` with permissions `beforeInitialize | beforeAddLiquidity | beforeSwap` (`0x2880`). Pure access-control gate: reverts every swap until `markSettled` is called; blocks non-manager liquidity adds pre-settlement; holds no funds; runs no price math. Shared across v1 and v2 — the same hook address gates every pool.
- **`src/SealedLaunch.sol`** — v1 manager. Factory + escrow + settlement (`IUnlockCallback`). Direct commitments, uniform clearing at window close, LP seeded at the clearing price, refunds on missed `minRaise`.
- **`src/CommitRevealLaunch.sol`** — v2 manager. Adds a hashed commit + masked deposit on top of v1's clearing. Bid sizes stay hidden on-chain until reveal.
- **`src/LaunchToken.sol`** — vanilla ERC-20 deployed per-launch by the manager. `offeredTokens` go pro-rata to revealers; `lpTokens` seed the v4 pool.

The hook address is CREATE2-mined (`HookMiner`) so its low bits carry the v4 permission flags. All managers initialize their pools against the official Uniswap v4 PoolManager on X Layer. Gas is paid in OKB.

## Live on X Layer mainnet (chain 196)

| Contract | Address | OKLink |
|---|---|---|
| v2 CommitRevealLaunch (manager) | `0xaeD6bd08CDBaD833312d6BCFd9F97954350F606e` | [view](https://www.oklink.com/xlayer/address/0xaeD6bd08CDBaD833312d6BCFd9F97954350F606e) |
| v1 SealedLaunch (manager) | `0xd6a240183eea10cd74f9911FE3f7717c90564B8C` | [view](https://www.oklink.com/xlayer/address/0xd6a240183eea10cd74f9911FE3f7717c90564B8C) |
| SealedLaunchHook (shared) | `0x594B539591e51e7981b05126B7e4d869C3BaA880` | [view](https://www.oklink.com/xlayer/address/0x594B539591e51e7981b05126B7e4d869C3BaA880) |
| Uniswap v4 PoolManager (official) | `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32` | [view](https://www.oklink.com/xlayer/address/0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32) |

The v2 demo poolId (settled lifecycle): `0x33bd0be4` `4367cc00fb0c59e15ce1385e` `3160b6a9f07a1b39676256dd67686cca` (concatenate without spaces).

The v2 demo ran end-to-end on mainnet with two distinct on-chain bidders: deployer (`0x53Dd…`) and `0xDAf2e49A…` posted asymmetric sealed bids (masked 1000 + 500 dUSD2), revealed real amounts (700 + 300 dUSD2) during the reveal window with the overage refunded, the auction cleared at one uniform price, both bidders claimed pro-rata allocations (280,000 + 120,000 SBID = 7:3), and a post-settlement swap traded the now-open pool. Full tx provenance lives in `broadcast/DeployCommitRevealDemo.s.sol/196/`, `broadcast/RevealCommitRevealDemo.s.sol/196/`, and `broadcast/SettleCommitRevealDemo.s.sol/196/`.

## Try it

Open the **[lifecycle viewer](https://sealedlaunch.gudman.xyz/app)** to drive any auction from one URL — defaults to the mainnet demo. Spin up your own launch from **[/app/create](https://sealedlaunch.gudman.xyz/app/create)**: deploy a fresh ERC-20 and open a v2 CommitRevealLaunch pool in one transaction with your own window, raise, and tick spacing. To preview a specific deployment, deep-link via `https://sealedlaunch.gudman.xyz/app?launch=<manager>&poolId=<id>` (only audited managers are trusted; unknown ones go read-only behind an explicit opt-in).

## Local dev quickstart

```bash
# contracts
forge test                                       # 72/72 (incl. live X Layer mainnet fork test)
forge test --match-contract CommitRevealLaunch   # v2 only

# SDK
cd sdk && npm install && npm run build && npm run typecheck

# dApp
cd app && npm install && npm run dev
```

Mainnet scripts assert `block.chainid == 196`; testnet scripts assert `1952`. Hook address is CREATE2-mined via `HookMiner`.

### Deploy your own v2 launch

The interactive path is **[/app/create](https://sealedlaunch.gudman.xyz/app/create)**: one tx, deploys an ERC-20 and opens a CommitRevealLaunch pool with your params. Programmatic equivalents live in `script/`:

```bash
# Reproduce the v2 demo: deploy a CR manager, mint demo dUSD2, open a launch, commit.
PRIVATE_KEY=0x... forge script script/DeployCommitRevealDemo.s.sol:DeployCommitRevealDemo \
  --rpc-url https://rpc.xlayer.tech --broadcast

# After the reveal window closes, anyone can call settle.
PRIVATE_KEY=0x... LAUNCH=0x... POOL_ID=0x... \
  forge script script/SettleCommitRevealDemo.s.sol:SettleCommitRevealDemo \
  --rpc-url https://rpc.xlayer.tech --broadcast
```

## Documentation

- [`sdk/README.md`](sdk/README.md) — viem-native TypeScript SDK (v0.1, in-tree). Full v2 read + write surface, thin v1 wrappers, `commitmentFor` byte-verified against the on-chain demo.
- [`app/README.md`](app/README.md) — Next.js 15 + React 19 + wagmi 2 dApp. Lifecycle viewer + create flow. Consumes the SDK via `file:../sdk`.
- [`docs/DESIGN-phase3-5.md`](docs/DESIGN-phase3-5.md) — contract-level design for later phases.
- [`docs/ERC-launch-covenants.md`](docs/ERC-launch-covenants.md) — draft EIP for on-chain launch covenants.
- [`ROADMAP.md`](ROADMAP.md) — phase plan from hackathon hook to fair-issuance rail.

## Internal security audit (2026-05-28) — disclosed findings

A full internal audit covering contracts, SDK, frontend and Foundry scripts was run on the day of the submission. **61 findings** across the four streams. The frontend, SDK and scripts findings are **patched in this commit** (see the commit log). The contract findings are deferred to a v1.1 / v2.1 redeploy because the live mainnet addresses cannot be patched in place — the deployed contracts are documented as known-limited v1.0. Contract source carries the v1.1 patches plus **10 new tests** covering them, but the **deployed v1.0 addresses are unchanged**.

| Stream | Findings | Status |
|---|---|---|
| Frontend | covered in 61 total | patched in this commit |
| SDK | covered in 61 total | patched in this commit |
| Foundry scripts | covered in 61 total | patched in this commit |
| Contracts | 2 CRITICAL + High/Medium | source-patched + 10 new tests; **live v1.0 addresses unchanged** |

**Critical findings on the LIVE mainnet contracts (do NOT use for multi-launch production):**

- **C-1 — `SealedLaunch.settle()` balance-sweep.** `src/SealedLaunch.sol:212-213` uses `quote.balanceOf(address(this))` to compute the launcher payout. If a second launch (legitimate or attacker-created) coexists on the same manager with the same quote token, settling either one drains the other's escrow to the settling launcher. Mitigated today by the manager hosting only the demo auction. **Do not host multiple concurrent launches on a single SealedLaunch v1 manager.**
- **C-2 — `CommitRevealLaunch` LP can over-consume the shared balance.** `src/CommitRevealLaunch.sol` doesn't `require(quoteUsed <= totalRevealed)` after the `unlock` callback, doesn't bound `tickSpacing` / `_sqrtPriceX96`, and shares its quote balance with other launches on the same manager. A pathological launch can pull more quote during LP seeding than it raised, drawing from non-revealer escrow or sibling launches. Mitigated today by the manager hosting only the demo auction.

**High-severity findings (also deferred to v1.1):**

- **H-3 — `settle()` brick on launcher-chosen inputs.** Bad `tickSpacing` / `minRaise=0` with zero reveals / extreme price math can revert `settle()` permanently, locking every committer out of reclaim. v1.1 must add a `failed` fallback when the math is out of bounds.
- **H-4 — `_activeKey` / `_activeId` reentrancy via ERC-777-style quote tokens.** Add `nonReentrant` modifiers on every external state-changing function.
- **H-5 — Same shared-balance class as C-2** for the launcher payout path in v2.
- **H-6 — Defense-in-depth `nonReentrant`** missing on the contract.
- **M-9 — `SealedLaunchHook.configure` is unrestricted** — front-runnable, can deny a legitimate launch by pre-configuring a pool id with a different manager.

**v1.1 / v2.1 fix plan (post-submission):**

1. Replace balance-sweep with per-launch quote accounting (`launcherProceeds = l.totalRevealed - quoteUsed`, already correct in v2 except for the missing bound on `quoteUsed`).
2. Add `require(quoteUsed <= l.totalRevealed)` and `tickSpacing` / sqrtPrice bounds validation.
3. Add `nonReentrant` on every external state-changing function.
4. Restrict `SealedLaunchHook.configure` to an allowlist of trusted managers.
5. New tests covering the cross-launch drain scenario (10 added — `forge test` is 72/72).
6. Redeploy to fresh mainnet addresses. The v1.0 demo addresses stay on-chain as historical proof.

**Frontend / SDK / scripts findings — patched in this commit:**

- Frontend: phishing-link allowlist (`KNOWN_LAUNCHES`) for `?launch=` query-param + opt-in ack; ActionPanel goes read-only on untrusted; `QuoteFaucet` chain-id gate + amount cap + cooldown; `ensureXLayerNetwork` uses the connected wallet's provider (not `window.ethereum`); Rabby-runbook only fires for actual Rabby; all action buttons disabled while pending; multi-tab race blocked via pre-commit `fetchBid`; `oklink` hrefs validated; `/create` ERC-20 sanity-call + strict input validation.
- SDK: `resolveChain(ctx)` throws if `WalletClient` has no chain (fixes wrong-chain broadcast); `createLaunch` result now includes the decoded `PoolKey`; `LP_FEE` ABI mutability corrected `view` → `pure`; `deriveSalt` normalizes to NFC; new `hasCommitted(b)` helper; unsafe `as` casts removed in reads; peer dep `viem ^2.21.0`.
- Foundry scripts: `require(block.chainid == 196)` on every mainnet script (closes the cross-chain footgun from the shared v4 PoolManager address on X Layer + Arbitrum); `require(== 1952)` on the testnet script; `DeployLiftoff.s.sol` standardized to envUint + keyed broadcast; `DEMO_TICK_SPACING` constant; `SKIP_DEMO_SWAP` env gate.

## Roadmap

- **Phase 0 — Built** ✅ — v4 hook + v1/v2 managers, 72/72 Foundry tests, real auction settled on X Layer mainnet.
- **Phase 1 — Win the hackathon** ✅ — deployed to mainnet, multi-bidder lifecycle settled on-chain, live state widget, demo video + submission.
- **Phase 2 — Hook → product** — commit-reveal v2 shipped; SDK v0.1 + hosted dApp v0.1 shipped in-tree; next: auction variants, OKB fee routing, third-party audit before real TVL.
- **Phase 3 — X Layer launch standard** — flap partnership as v4-native fair-launch mode; launchpad-as-a-service; fairness reputation; OKX OnchainOS skill + OKB-denominated fees.
- **Phase 4 — Smarter auctions + multi-chain** — tiered / Dutch curves, allowlist/KYC gates, NFT vesting, anti-dump covenants; deploy on every chain with official v4 (Base, Arbitrum, Unichain, Ink, …).
- **Phase 5 — Moonshot** — the fair-issuance rail for token markets; open standard other launchpads adopt; potentially an EIP for on-chain launch covenants.

## Tests

```bash
forge test                                       # 72/72 (61 prior + 1 live mainnet fork + 10 new v1.1 audit tests)
forge test --match-contract SealedLaunchTest     # v1 sealed batch auction
forge test --match-contract CommitRevealLaunch   # v2 commit-reveal sealed-bid
```

The headline test, `test_sniperFirstBlockSamePricePerTokenAsLastBlock`, proves a first-block "sniper" and a last-block buyer receive identical allocation and identical price per token. The live mainnet fork test verifies the hook + manager wire-up against the real X Layer v4 PoolManager at the live block. The 10 new audit tests cover the v1.1 invariants (per-launch quote accounting, `quoteUsed <= totalRevealed`, manager allowlist, reentrancy guards, bounds checks).

## Built for

OKX **Build X — Hook the Future** hackathon. Uniswap v4 · X Layer · flap.sh. Tags: [@XLayerOfficial](https://x.com/XLayerOfficial) · [@Uniswap](https://x.com/Uniswap) · [@flapdotsh](https://x.com/flapdotsh).

## License

[MIT](LICENSE).

---

[@sealedlaunch](https://x.com/sealedlaunch) · [github.com/Ridwannurudeen/liftoff](https://github.com/Ridwannurudeen/liftoff)
