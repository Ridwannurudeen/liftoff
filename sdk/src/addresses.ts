import type { Address } from "viem";

/** X Layer mainnet (chain id 196) — the canonical Sealed Launch deployment. */
export const X_LAYER_MAINNET_ID = 196 as const;

/** Official Uniswap v4 PoolManager on X Layer mainnet. */
export const X_LAYER_POOL_MANAGER: Address =
  "0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32";

/**
 * Shared `BaseHook` that gates the pool until the auction settles. Both
 * v1 (`SealedLaunch`) and v2 (`CommitRevealLaunch`) wire pools through this
 * exact hook — it tracks gating state per pool id.
 */
export const SEALED_LAUNCH_HOOK: Address =
  "0x594B539591e51e7981b05126B7e4d869C3BaA880";

/**
 * v1 — uniform-price batch auction. Commitments visible on-chain; fairness
 * comes from uniform clearing + no pre-settlement trading.
 */
export const SEALED_LAUNCH_V1: Address =
  "0xd6a240183eea10cd74f9911FE3f7717c90564B8C";

/**
 * v2 — hashed commit + masked deposit + reveal. Adds size-sealed bids
 * (real bid amounts stay hidden on-chain until the reveal window).
 */
export const COMMIT_REVEAL_LAUNCH_V2: Address =
  "0xaed6BD08CDBaD833312d6BcFd9F97954350F606e";

/**
 * Default v0.1 mainnet preset — pass to `getContracts({ chainId: 196 })`
 * to fetch a ready-made record of all the addresses above.
 */
export const X_LAYER_CONTRACTS = {
  chainId: X_LAYER_MAINNET_ID,
  poolManager: X_LAYER_POOL_MANAGER,
  hook: SEALED_LAUNCH_HOOK,
  v1: SEALED_LAUNCH_V1,
  v2: COMMIT_REVEAL_LAUNCH_V2,
} as const;
