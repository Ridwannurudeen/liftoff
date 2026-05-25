# Liftoff — OKX "Hook the Future" submission

> Fill the three bracketed placeholders after deploy + video, then submit via the Google Form. Do not submit without final review.

**Project name:** Liftoff

**One-liner:** A fair-launch + fair-life Uniswap v4 hook on X Layer — a token launches *as* a v4 pool, with anti-snipe, locked liquidity, automatic graduation, and post-launch anti-dump, all in one hook.

**What it does / problem it solves:**
Launchpads on X Layer today run a bonding-curve contract in front of an AMM, then migrate the token into a frozen pool — two systems, a migration step, and no protection against snipers or post-launch dumps. Liftoff collapses the whole lifecycle into a single Uniswap v4 hook on one pool:
1. **Anti-snipe** — a time-decaying launch fee on buys (v4 dynamic fees) + per-tx and per-wallet buy caps during the opening window.
2. **Rug protection** — liquidity removal is locked until a configurable timestamp.
3. **Graduation** — the pool auto-flips to its baseline fee once cumulative volume or the window is reached.
4. **Anti-dump ("fair life")** — after graduation, sells are capped per tx, per wallet, and as a % of pool reserves to prevent cliff dumps — a covenant a normal ERC-20 can't enforce.

**Uniswap v4 / X Layer components used:**
- Uniswap v4 hook (`BaseHook`) using dynamic fees (`LPFeeLibrary` override), `beforeInitialize/beforeSwap/afterSwap/beforeRemoveLiquidity`.
- Deployed against the official Uniswap v4 **PoolManager on X Layer mainnet** `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`.
- `LaunchFactory` for one-transaction launches; HookMiner CREATE2 address mining.
- `LiftoffRouter` forwards the end user in hookData so per-wallet caps are enforced reliably (tx.origin fallback otherwise); caps are checked in `afterSwap` on the realized `BalanceDelta`, so they hold for exact-input and exact-output swaps.

**Why it matters (market):** Directly serves X Layer's launchpad ecosystem (e.g. flap.sh) — adoptable as a v4-native launch mode; grows v4 pools, OKB gas, and real users.

**Verification / completion:** 27/27 Foundry tests, including a **live fork test against the real X Layer PoolManager** and a narrated end-to-end lifecycle demo.

**Deployed on X Layer mainnet (chainId 196, against the official Uniswap v4 PoolManager):**
- **Liftoff hook:** `0xA03D3d9043324955a4ea2a1bE77352851611E2C0` — https://www.oklink.com/xlayer/address/0xA03D3d9043324955a4ea2a1bE77352851611E2C0
- **LiftoffRouter:** `0x834bad8990a4a363A4468723fe74f2468f6aECE1` — https://www.oklink.com/xlayer/address/0x834bad8990a4a363A4468723fe74f2468f6aECE1
- **LaunchFactory:** `0x52bFAB995e1f6e8C875Be9d95aBa29bc15f756D5` — https://www.oklink.com/xlayer/address/0x52bFAB995e1f6e8C875Be9d95aBa29bc15f756D5
- **Demo token (LIFT):** `0x8b6cd1Dec298C0B9d6aF59f01dC501DB90b75AbE` — https://www.oklink.com/xlayer/address/0x8b6cd1Dec298C0B9d6aF59f01dC501DB90b75AbE
- The deploy ran the full lifecycle on-chain (launch-fee buys → graduation by volume → baseline buy/sell), so Hook behavior is triggered by real transactions and inspectable on OKLink. All deploy/lifecycle tx hashes are in `broadcast/DeployMainnetStack.s.sol/196/run-latest.json`.

**Links:**
- Live site: https://liftoff.gudman.xyz (reads the deployed hook's state live from X Layer)
- GitHub: https://github.com/Ridwannurudeen/liftoff
- Demo video (2–5 min): `[ADD YOUTUBE/LOOM URL]`

**Required social post:** see `X_POST.md` (tags @XLayerOfficial @Uniswap @flapdotsh).
