/**
 * Minimal ABI fragment for `SealedLaunchHook`. The SDK only reads `isSettled` —
 * the gating hook holds no balances and runs no price math, so write methods
 * are deliberately omitted (configure/markSettled are manager-only and called
 * from inside the v1/v2 manager contracts).
 */
export const sealedLaunchHookAbi = [
  {
    type: "function",
    name: "isSettled",
    stateMutability: "view",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;
