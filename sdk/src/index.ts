// Addresses + chain preset.
export {
  COMMIT_REVEAL_LAUNCH_V2,
  SEALED_LAUNCH_HOOK,
  SEALED_LAUNCH_V1,
  X_LAYER_CONTRACTS,
  X_LAYER_MAINNET_ID,
  X_LAYER_POOL_MANAGER,
} from "./addresses.js";

// ABIs (consumers can pass these to viem/wagmi directly).
export { commitRevealLaunchAbi } from "./abi/commit-reveal.js";
export { sealedLaunchAbi } from "./abi/sealed-launch.js";
export { sealedLaunchHookAbi } from "./abi/hook.js";

// v2 — CommitRevealLaunch (primary).
export type {
  Bid,
  Launch,
  LaunchParams,
  PoolId,
  PoolKey,
} from "./commit-reveal/types.js";
export {
  commitmentFor,
  deriveSalt,
  type CommitmentInput,
} from "./commit-reveal/commitment.js";
export {
  allocationOf,
  clearingPrice,
  getBid,
  getLaunch,
  phaseOf,
  totalRevealed,
  type Phase,
  type ReadArgs,
} from "./commit-reveal/reads.js";
export {
  claim,
  commit,
  createLaunch,
  reclaim,
  reveal,
  settle,
  type CommitArgs,
  type CreateLaunchResult,
  type RevealArgs,
  type WriteCtx,
} from "./commit-reveal/writes.js";

// v1 — SealedLaunch (thin wrappers, retained because it's also live on mainnet).
export type { PoolId as PoolIdV1, SealedLaunch } from "./sealed/types.js";
export {
  clearingPriceV1,
  getLaunchV1,
  totalCommitted,
  type ReadArgs as ReadArgsV1,
} from "./sealed/reads.js";
export {
  claimV1,
  commitV1,
  refundV1,
  settleV1,
  type WriteCtxV1,
} from "./sealed/writes.js";

// Hook — shared by v1 and v2.
export { isSettled } from "./hook/reads.js";
