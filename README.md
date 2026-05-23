# Liftoff — a fair-launch + fair-life Uniswap v4 hook on X Layer

Liftoff turns a Uniswap v4 pool into a complete token-launch venue. A token launches **as** a v4 pool — no separate bonding-curve contract, no migration step — and a single hook governs its whole lifecycle:

1. **Anti-snipe** — a time-decaying launch fee on buys (via v4 dynamic fees) plus a per-tx buy cap during the opening window, so bots can't snipe block one.
2. **Rug protection** — liquidity removal is locked until a configurable timestamp.
3. **Graduation** — once cumulative volume (or the launch window) is reached, the pool flips to its baseline fee automatically.
4. **Anti-dump (the "fair life")** — after graduation, sells are capped per tx to prevent cliff dumps.

Built for the OKX **Build X "Hook the Future"** hackathon. Deployed against the **official Uniswap v4 PoolManager on X Layer mainnet** (`0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`).

## Why it matters

Launchpads on X Layer (e.g. flap.sh) today run a bonding-curve contract *in front of* an AMM, then migrate the token into a frozen pool — two systems, a migration risk, and no anti-snipe. Liftoff collapses all of that into one hook on one v4 pool: the launch curve, anti-snipe window, rug lock, graduation, and post-launch anti-dump are native pool behavior. It's a primitive a launchpad can adopt directly.

## How it maps to the judging criteria

- **Innovation** — Liftoff isn't a port of an existing protocol; it builds a new launch market structure on the v4 curve. Most launch hooks stop at a fair *launch*; Liftoff adds a post-graduation **anti-dump covenant** — fairness across the token's whole life, enforced at the swap layer (something a plain ERC-20 can't do). The full lifecycle (fee decay, graduation, cap lifting) runs autonomously on-chain with no operator.
- **Market Potential** — every memecoin/creator launch needs anti-snipe + anti-rug + anti-dump; Liftoff serves X Layer's launchpad ecosystem (e.g. flap.sh) as an adoptable v4-native launch mode, growing v4 pools, liquidity, users, and OKB gas.
- **Completion** — 22/22 Foundry tests, including a **live fork test against the real X Layer v4 PoolManager** and a narrated end-to-end lifecycle; the deploy script triggers real on-chain swaps judges can inspect on OKLink.

## Architecture

`src/Liftoff.sol` is a single `BaseHook` with permissions `beforeInitialize | beforeSwap | afterSwap | beforeRemoveLiquidity`.

- `configureLaunch(PoolKey, LaunchConfig)` — set the launch terms (called once, before pool init; pool must be a dynamic-fee pool).
- `_beforeInitialize` — requires the launch is configured and the pool is dynamic-fee; stamps the launch start.
- `_beforeSwap` — applies the decaying launch fee on buys (returns a fee with `LPFeeLibrary.OVERRIDE_FEE_FLAG`), enforces the pre-graduation buy cap and the post-graduation sell cap.
- `_afterSwap` — accumulates quote volume and graduates the pool when the threshold or window is met.
- `_beforeRemoveLiquidity` — blocks liquidity removal until `lpLockUntil`.

```
LaunchConfig {
  bool   tokenIsCurrency0;   uint24 startFee; uint24 endFee; uint24 baselineFee;  // fees in pips (1e6 = 100%)
  uint64 launchWindow;       uint256 maxBuyPerTx;  uint256 graduationVolume;
  uint64 lpLockUntil;        uint256 maxSellPerTx;
}
```

## Test

```bash
forge test                                   # full suite (22 tests)
forge test --match-contract LiftoffTest      # unit tests (10)
forge test --match-contract LiftoffForkTest  # live fork vs X Layer PoolManager
```

## Deploy to X Layer

Hook only:

```bash
forge script script/DeployLiftoff.s.sol:DeployLiftoff \
  --rpc-url https://rpc.xlayer.tech --private-key $PRIVATE_KEY --broadcast
```

Full lifecycle demo (deploys hook + `LaunchFactory`, launches a token, seeds liquidity, and runs launch buys → graduation → baseline buy/sell so judges can inspect real on-chain activity):

```bash
forge script script/DeployMainnetStack.s.sol:DeployMainnetStack \
  --rpc-url https://rpc.xlayer.tech --private-key $PRIVATE_KEY --broadcast
```

Both mine a CREATE2 salt so the hook address carries the right permission bits (`HookMiner`) and deploy against the official X Layer v4 PoolManager. Gas is paid in **OKB**. Verify on OKLink: https://www.oklink.com/xlayer

## X Layer

- Mainnet chainId **196**, RPC `https://rpc.xlayer.tech`, gas token **OKB**, explorer https://www.oklink.com/xlayer
- Uniswap v4 PoolManager (official): `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`

## Honest scope notes

- Buy/sell caps are **per-transaction**, not per-wallet — v4 sees the swap router as `msg.sender`, so true per-wallet limits need `tx.origin` or routing through a trusted router that passes the end-user in `hookData` (documented as future work). Per-tx caps still stop atomic single-tx snipes and dumps.
- Cap checks use `|amountSpecified|` (exact-input is the common path); exact-output sizing is approximate.
- The hook gives launch terms a lot of power over a pool; pools should be created by the launcher with terms users can read on-chain via `configs(poolId)`.
