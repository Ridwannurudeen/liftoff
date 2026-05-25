# Liftoff — Roadmap

**North star:** become the *fairness layer for token launches* — the default way a token comes to market on X Layer, then on any Uniswap v4 chain. Fair to buy (no snipes), safe to hold (no rug), hard to dump (no cliff) — all enforced natively in the pool, not bolted on.

---

## Phase 0 — Built ✅ (hackathon core)
- `Liftoff` v4 hook: anti-snipe decaying fee + per-tx & per-wallet buy caps, LP lock, automatic graduation, post-graduation anti-dump (per-tx, per-wallet, and %-of-reserve sell caps), all enforced in `afterSwap` on realized amounts (correct for exact-input and exact-output).
- `LiftoffRouter` for reliable per-wallet enforcement (tx.origin fallback) + `LaunchFactory` for one-transaction launches.
- 27/27 tests, including a **live fork test against the real X Layer PoolManager**.
- Standalone X Layer deploy scripts (HookMiner CREATE2), README.

## Phase 1 — Win the hackathon (now → submission)
- Deploy to **X Layer mainnet** (OKB gas) → publish the verifiable contract address.
- **Reference launch**: spin up a real demo token + Liftoff pool and run the full lifecycle on-chain — a sniper bot gets taxed, the pool graduates, a cliff-dump is blocked — captured in the 2–5 min video.
- Submit: public GitHub, X post (@XLayerOfficial @Uniswap @flapdotsh), Google Form.
- Judge-delight stretch: a one-page launch UI (configure → launch → live fee/graduation/anti-dump status) + the sniper-bot demo script.

## Phase 2 — From hook to product (≈ weeks 1–6 after)
- **Done ✅:** per-wallet caps via the trusted `LiftoffRouter` (tx.origin fallback); graded sell limits as a % of reserves; exact-output-correct enforcement; one-tx `LaunchFactory`.
- **Fee routing:** split swap fees to creator + protocol treasury, settled in **OKB** (optional x402 flow).
- **`liftoff-sdk`** (TypeScript) + a hosted launch dApp.
- **Security:** invariant + fuzz tests, then a **third-party audit** before any real TVL. (Non-negotiable before real money — the current build is hackathon-grade.)

## Phase 3 — Become the X Layer launch standard (≈ months 2–4)
- **flap partnership** (the 1st-prize lever): ship Liftoff as flap's v4-native launch mode on X Layer, replacing the curve→migration flow.
- **Launchpad-as-a-service:** other apps embed Liftoff via the SDK; small protocol fee on launches.
- **Fairness reputation:** per-launch fairness score + creator track record (reuses ERC-8004 / reputation tooling).
- **OKX integration:** OnchainOS skill, DEX-aggregator listing, OKB-denominated fees.

## Phase 4 — Advanced mechanics + multi-chain (≈ months 4–9)
- **Smarter fairness:** Dutch-auction launches; **sniper-value-recapture** (redistribute sniper overpayment to genuine early buyers); vesting positions as NFTs; volatility-aware anti-dump curves.
- **Multi-chain:** deploy on every chain with official v4 (Base, Arbitrum, Unichain, Ink, …) — same hook, far larger TAM.
- Optional governance/token; LP + creator fee-sharing.

## Phase 5 — Moonshot
The fairness rail for token markets: every fair launch routes through Liftoff; an open standard other launchpads adopt; potentially an EIP for on-chain launch covenants.

---

## Honest risks & dependencies
- **Audit gate:** today's hook is contest-grade; a real launchpad handling user funds needs an audit first.
- **Per-wallet enforcement** relies on the trusted `LiftoffRouter` to carry the user in `hookData`; the `tx.origin` fallback for other routers is best-effort (spoofable by a malicious router, breaks under account abstraction).
- **Partnership/adoption** (flap, OKX) cannot be assumed — it must be earned.
- **Regulatory:** launchpads + transfer covenants touch securities-adjacent territory; jurisdictional care required.
- **Ecosystem maturity:** v4 liquidity on X Layer is still early — upside, but not yet deep.
