# ERC-XXXX: On-Chain Launch Covenants for AMM Pools

> **Status:** Draft (not yet submitted to the Ethereum EIPs repository)
> **Type:** Standards Track · **Category:** ERC
> **Requires:** Uniswap v4 hooks (`IHooks`), dynamic LP fees
> **Created:** 2026-05-25
> **Reference implementation:** [Liftoff](../src/Liftoff.sol) — live on X Layer mainnet (chain 196), hook `0xA03D3d9043324955a4ea2a1bE77352851611E2C0`

## Abstract

This standard defines a minimal interface for a **launch covenant**: a set of fairness rules
bound to a single AMM pool at creation time and enforced by the pool's swap/liquidity hooks for
the life of the token. A covenant covers four phases of a token's life — opening (anti-snipe),
holding (liquidity lock), graduation (transition to normal trading), and maturity (anti-dump) —
expressed as on-chain, publicly-readable terms rather than off-chain promises.

The goal is interoperability: wallets, launchpads, explorers, and aggregators can read a single
interface to learn a pool's launch terms and current lifecycle state, regardless of which hook
implementation issued them.

## Motivation

Token launches today rely on a bonding-curve contract *in front of* an AMM, followed by a
migration into a frozen pool. This creates two trust surfaces, a migration step, and no native
protection against snipers (block-one buys) or post-launch cliff dumps. The protections that do
exist (vesting, locks) live in bespoke contracts that no two launchpads expose the same way, so
nothing downstream can read them uniformly.

A v4 hook can already enforce all of these rules inside one pool. What is missing is a *standard
surface* so that the rules — and the live lifecycle state — are machine-readable. With one
interface:

- A wallet can warn a user "this pool's launch fee is currently 80%, decaying to 0.3% over 1h."
- An explorer can show "liquidity locked until <timestamp>; graduates at <volume>."
- An aggregator can decide whether a pool has graduated to normal trading before routing to it.
- A launchpad can adopt any conforming hook without re-integrating per implementation.

## Specification

The key words MUST, SHOULD, and MAY are to be interpreted as described in RFC 2119.

A conforming **launch covenant** is a Uniswap v4 hook with at least the
`beforeInitialize`, `beforeSwap`, `afterSwap`, and `beforeRemoveLiquidity` permissions, that
implements `ILaunchCovenant`:

```solidity
interface ILaunchCovenant {
    /// @notice Lifecycle phase of a covenant pool.
    enum Phase { Unconfigured, Launching, Graduated }

    /// @notice The immutable-after-init terms of a launch.
    struct Covenant {
        uint24  startFee;            // opening buy fee, pips (1e6 = 100%)
        uint24  endFee;              // buy fee at window close, pips
        uint24  baselineFee;         // fee after graduation, pips
        uint64  launchWindow;        // anti-snipe window length, seconds
        uint64  lpLockUntil;         // unix ts before which LP cannot be removed
        uint256 graduationVolume;    // cumulative quote volume that graduates the pool
        uint256 maxBuyPerTx;         // 0 = disabled
        uint256 maxBuyPerWallet;     // 0 = disabled
        uint256 maxSellPerTx;        // 0 = disabled
        uint256 maxSellPerWallet;    // 0 = disabled
        uint16  maxSellBpsOfReserve; // post-graduation per-sell cap, bps of reserve; 0 = disabled
    }

    /// @notice MUST be emitted when a pool's covenant is set, before pool initialization.
    event CovenantConfigured(bytes32 indexed poolId, address indexed configurer);
    /// @notice MUST be emitted exactly once when a pool transitions to `Graduated`.
    event Graduated(bytes32 indexed poolId, uint256 cumulativeVolume, uint64 at);

    /// @notice Bind a covenant to a pool. MUST revert if the pool is already configured,
    ///         if called after pool initialization, or if the pool is not a dynamic-fee pool.
    function configureCovenant(bytes32 poolId, Covenant calldata terms) external;

    /// @notice The terms bound to `poolId`. MUST revert if unconfigured.
    function covenantOf(bytes32 poolId) external view returns (Covenant memory);

    /// @notice The current lifecycle phase of `poolId`.
    function phaseOf(bytes32 poolId) external view returns (Phase);

    /// @notice The LP fee (pips) a buy would currently pay, ignoring any override flag.
    function currentBuyFee(bytes32 poolId) external view returns (uint24);
}
```

### Lifecycle semantics

1. **Configure → initialize.** `configureCovenant` MUST be called before the pool is initialized.
   The pool MUST be a dynamic-fee pool. After initialization, terms MUST NOT change.
2. **Launching.** Until graduation, the hook MUST apply a buy fee that decays monotonically from
   `startFee` to `endFee` across `launchWindow`, and MUST enforce any configured buy caps.
3. **Graduation.** The hook MUST transition to `Graduated` (and emit `Graduated`) the first time
   either cumulative quote volume reaches `graduationVolume` or `launchWindow` elapses, after which
   the buy fee MUST be `baselineFee`.
4. **Maturity.** After graduation the hook MUST enforce any configured sell caps.
5. **Liquidity lock.** `beforeRemoveLiquidity` MUST revert before `lpLockUntil`.

### Quantity enforcement

Caps SHOULD be enforced in `afterSwap` against the realized `BalanceDelta`, so that they hold for
both exact-input and exact-output swaps. Per-wallet caps require the end-user address; because v4
passes the *router* as the swap `sender`, an implementation MAY accept the user address via
`hookData` from a trusted router and SHOULD document its fallback (e.g. `tx.origin`) and that
fallback's limitations.

## Rationale

- **Pool-scoped, not token-scoped.** Covenants attach to a `poolId`, not an ERC-20, so an ordinary
  fixed-supply token gains launch protections without a custom token contract.
- **Read-only state surface.** `phaseOf` / `currentBuyFee` / `covenantOf` let any consumer reason
  about a pool without simulating a swap.
- **Dynamic fee, not transfer hooks.** Fees are expressed through v4 dynamic fees rather than
  ERC-20 transfer taxes, keeping the token a standard ERC-20 and confining policy to the pool.
- **Minimal required permission set.** The four hook permissions are the smallest set that can
  enforce the four phases.

## Backwards Compatibility

This is additive. Conforming hooks are ordinary v4 hooks; pools without a covenant are unaffected.
Tokens remain standard ERC-20s. Consumers that don't understand the interface simply ignore it.

## Reference Implementation

[Liftoff](../src/Liftoff.sol) implements the full lifecycle and is deployed and exercised on X
Layer mainnet. The naming differs slightly (`configureLaunch`/`states`/`configs`); the
[design doc](./DESIGN-phase3-5.md) tracks aligning Liftoff's public surface to this interface.

## Security Considerations

- **Configurer trust.** Whoever calls `configureCovenant` sets terms that bind all traders; pools
  SHOULD be created by the launcher and terms read by users before trading.
- **Per-wallet caps are best-effort off the trusted router.** `tx.origin`-based attribution is
  spoofable by a malicious router and breaks under account abstraction.
- **Fee bounds.** Implementations MUST bound fees by the AMM's maximum LP fee and reject
  `startFee < endFee` or zero windows.
- **No upgrade path for terms.** Terms are immutable after initialization by design; a covenant bug
  cannot be patched on a live pool, so implementations SHOULD be audited before real TVL.

## Copyright

Released to the public domain via CC0.
