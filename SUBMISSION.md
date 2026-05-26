# Sealed Launch — OKX "Hook the Future" submission

> Fill the video URL after recording, then submit via the Google Form. Do not submit without final review.

**Project name:** Sealed Launch

**One-liner:** An order-independent fair-launch hook for Uniswap v4 on X Layer — a token launches through a sealed, uniform-price batch auction inside the hook, so being first (or paying to be first) buys no advantage.

**What it does / problem it solves:**
Token launches get sniped on block one. Every existing defense (fee decay, Dutch auctions, fixed-price windows) still lets the fastest/best-connected actor in first. X Layer makes this worse and better at once: it migrated to the OP Stack with a **flashblocks** sequencer, and we verified on real mainnet blocks that transactions are **not** ordered by priority fee — ordering is unpredictable. So rather than fight ordering, Sealed Launch makes it **irrelevant**:
1. During the launch window the hook **blocks all swaps** — nobody can trade the token before it clears.
2. Buyers **commit** quote tokens. Commit order and block position don't matter.
3. At window close, everyone **clears at one uniform price**, pro-rata: `allocation = offeredTokens · committed / totalCommitted`.
4. Settlement **initializes the pool at the clearing price**, **seeds liquidity**, and opens normal trading. A missed `minRaise` refunds everyone.

Fairness is a property of the mechanism, not a tunable parameter — provably un-snipeable.

**Uniswap v4 / X Layer components used:**
- `SealedLaunchHook` (`BaseHook`, permissions `beforeInitialize | beforeAddLiquidity | beforeSwap`) gates the pool: swaps revert until settled; non-manager liquidity adds revert pre-settlement (no LP front-running).
- `SealedLaunch` (`IUnlockCallback`) escrows commitments and, at settlement, initializes + seeds the pool via `poolManager.unlock` → `modifyLiquidity` at the clearing price.
- Deployed against the official Uniswap v4 **PoolManager on X Layer mainnet** `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`; hook address CREATE2-mined with `HookMiner`.

**Why it matters (market):** Every token launch needs anti-snipe. Sealed Launch is directly adoptable by X Layer launchpads — **flap.sh** (a hackathon co-initiator) has no anti-snipe today — and grows v4 pools, liquidity, real users and OKB gas on a chain whose v4 TVL is still tiny.

**Verification / completion:** 62/62 Foundry tests, including a **live X Layer mainnet fork test**, plus a **real auction settled on mainnet**. The headline test proves a first-block buyer and a last-block buyer receive identical allocation and identical price per token. v2 commit-reveal (`src/CommitRevealLaunch.sol`, 12 dedicated tests) is shipped in-tree as the documented hardening path — bid sizes hidden via hashed commit + reveal — live demo still runs v1.

**Deployed + demonstrated on X Layer mainnet (chain 196, official Uniswap v4 PoolManager):**
- **SealedLaunchHook:** `0x594B539591e51e7981b05126B7e4d869C3BaA880` — https://www.oklink.com/xlayer/address/0x594B539591e51e7981b05126B7e4d869C3BaA880
- **SealedLaunch (manager):** `0xd6a240183eea10cd74f9911FE3f7717c90564B8C` — https://www.oklink.com/xlayer/address/0xd6a240183eea10cd74f9911FE3f7717c90564B8C
- **SEAL (demo token):** `0x9A758af7A7EAB7B7F038caC7AA6127d232fC159B` — https://www.oklink.com/xlayer/address/0x9A758af7A7EAB7B7F038caC7AA6127d232fC159B
- **dUSD (demo quote):** `0x8FfBcEdbD23B128b2652a2a2786515DdEF131182` — https://www.oklink.com/xlayer/address/0x8FfBcEdbD23B128b2652a2a2786515DdEF131182
- A real launch ran end-to-end: open auction → commit → settle at the uniform clearing price → seed LP → live swap. Verified on-chain: `isSettled = true`, pool liquidity `> 0`. Tx provenance in `broadcast/DeploySealedLaunch.s.sol/196/` and `broadcast/SettleSealedLaunch.s.sol/196/`.

**Links:**
- Live site: https://liftoff.gudman.xyz (reads the deployed auction's state live from X Layer)
- GitHub: https://github.com/Ridwannurudeen/liftoff
- Demo video (1–3 min): `[ADD YOUTUBE/LOOM URL]`

**Required social post:** see `X_POST.md` (tags @XLayerOfficial @Uniswap @flapdotsh).

---

*Predecessor: this repo began as **Liftoff** (a fair-launch + fair-life hook with time-decaying fee, LP lock, graduation, anti-dump caps), also deployed on X Layer mainnet (hook `0xA03D3d9043324955a4ea2a1bE77352851611E2C0`) and retained as the documented v1. Sealed Launch supersedes it with an order-independent mechanism suited to X Layer's flashblock sequencer.*
