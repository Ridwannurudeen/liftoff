# Sealed Launch — Roadmap

> Sealed Launch is an order-independent, uniform-price **sealed batch-auction launch hook** for Uniswap v4 on X Layer. This repo began as **Liftoff** (a fair-launch hook with decaying fee, LP lock, graduation, anti-dump caps), retained as the documented v1; Sealed Launch supersedes it with fairness enforced at the *mechanism* level. See [`README`](README.md).

**North star:** become the **fair-issuance layer for token launches** — the default way a token comes to market on X Layer, then on any Uniswap v4 chain. A launch where being first, best-connected, or highest-gas buys you *nothing*: one batch, one price, pro-rata to everyone.

---

## Phase 0 — Built ✅ (hackathon)
- `SealedLaunchHook` (v4 `BaseHook`; permissions `beforeInitialize | beforeAddLiquidity | beforeSwap`) — gates the pool: swaps revert and non-manager liquidity adds revert until the auction settles, so nobody can trade or front-run liquidity before clearing.
- `SealedLaunch` (`IUnlockCallback`) — escrows commitments; at window close clears at one uniform price (`allocation = offered · committed / totalCommitted`), then `poolManager.unlock → modifyLiquidity` seeds the pool at the clearing price and opens trading; a missed `minRaise` refunds everyone.
- **50/50 Foundry tests**, incl. a **live X Layer mainnet fork test** and the headline order-independence proof (a first-block buyer and a last-block buyer receive identical allocation and identical price per token).
- Standalone X Layer deploy + settle scripts (HookMiner CREATE2), live state site, README.

## Phase 1 — Win the hackathon (now → submission)
- **Done ✅:** deployed to **X Layer mainnet** against the official v4 PoolManager, with verifiable addresses; a **real auction settled on-chain** (commit → uniform clearing → LP seeded → live swap); live read-only state widget on the site.
- **Remaining (user):** 2–3 min demo video, X post (@XLayerOfficial @Uniswap @flapdotsh), Google Form submission.
- Stretch: a multi-committer demo (2+ wallets, one clearing price) to show pro-rata fairness directly on-chain.

## Phase 2 — From hook to product (≈ weeks 1–6)
- **Commit-reveal sealed bids (v2):** today the auction is order-*independent* but commitment *amounts* are visible on-chain — add a hashed commit + reveal so bid sizes stay hidden until settlement (true sealed-bid).
- **Auction variants:** recurring/scheduled launches, configurable window + `minRaise`, oversubscription / partial-fill refunds.
- **Fee routing:** post-launch swap fees split to creator + protocol treasury, settled in **OKB** (optional x402 flow).
- **`sealed-launch-sdk`** (TypeScript) + a hosted launch dApp (configure → auction → live clearing/allocation status).
- **Security:** invariant + fuzz tests, then a **third-party audit before any real TVL** (non-negotiable — the current build is hackathon-grade).

> Contract-level design for later phases: [`docs/DESIGN-phase3-5.md`](docs/DESIGN-phase3-5.md) · standard draft: [`docs/ERC-launch-covenants.md`](docs/ERC-launch-covenants.md).

## Phase 3 — Become the X Layer launch standard (≈ months 2–4)
- **flap partnership** (the 1st-prize lever): ship Sealed Launch as flap's v4-native fair-launch mode on X Layer — flap has no anti-snipe today.
- **Launchpad-as-a-service:** other apps embed Sealed Launch via the SDK; small protocol fee per launch.
- **Fairness reputation:** per-launch fairness score + creator track record (reuses ERC-8004 / reputation tooling).
- **OKX integration:** OnchainOS skill, DEX-aggregator listing, OKB-denominated fees.

## Phase 4 — Advanced mechanics + multi-chain (≈ months 4–9)
- **Smarter auctions:** tiered / Dutch clearing curves; allowlist- or KYC-gated raises for compliant launches; vesting allocations as NFTs; anti-dump covenants layered on the post-launch pool (the Liftoff v1 toolkit, now optional modules).
- **Multi-chain:** deploy on every chain with official v4 (Base, Arbitrum, Unichain, Ink, …) — same hook, far larger TAM.
- Optional governance/token; LP + creator fee-sharing.

## Phase 5 — Moonshot
The **fair-issuance rail** for token markets: every fair launch routes through a sealed batch auction; an open standard other launchpads adopt; potentially an **EIP for on-chain launch covenants** (draft in [`docs/ERC-launch-covenants.md`](docs/ERC-launch-covenants.md)).

---

## Honest risks & dependencies
- **Audit gate:** today's hook is contest-grade; a launchpad handling user funds needs an audit first.
- **"Sealed" today = order-independent, not hidden:** commitment amounts are on-chain until commit-reveal ships (Phase 2). Fairness currently comes from uniform pricing + no pre-settlement trading, not yet from concealed bids.
- **Partnership / adoption** (flap, OKX) must be earned, not assumed.
- **Regulatory:** batch-auction token issuance is securities-adjacent; jurisdictional care required.
- **Ecosystem maturity:** v4 liquidity on X Layer is still early — upside, but thin today.

---

*v1 predecessor: **Liftoff** — a fair-launch + fair-life hook (decaying launch fee, per-tx/per-wallet caps, LP lock, graduation, anti-dump), deployed on X Layer mainnet (hook `0xA03D3d9043324955a4ea2a1bE77352851611E2C0`) and retained as documented history. Sealed Launch supersedes it with order-independent fairness suited to X Layer's flashblocks sequencer.*
