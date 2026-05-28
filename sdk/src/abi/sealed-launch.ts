/**
 * ABI for `SealedLaunch` (v1). Smaller than v2 — bid sizes are visible
 * on-chain so there's no commit/reveal split, just `commit` then `settle`.
 */
export const sealedLaunchAbi = [
  // --- reads ---
  {
    type: "function",
    name: "totalCommitted",
    stateMutability: "view",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "clearingPrice",
    stateMutability: "view",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [{ name: "", type: "uint160" }],
  },
  {
    type: "function",
    name: "getLaunch",
    stateMutability: "view",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "token", type: "address" },
          { name: "quote", type: "address" },
          { name: "launcher", type: "address" },
          { name: "totalSupply", type: "uint256" },
          { name: "offeredTokens", type: "uint256" },
          { name: "lpTokens", type: "uint256" },
          { name: "startTime", type: "uint64" },
          { name: "endTime", type: "uint64" },
          { name: "minRaise", type: "uint256" },
          { name: "maxCommitPerWallet", type: "uint256" },
          { name: "tickSpacing", type: "int24" },
          { name: "tokenIsCurrency0", type: "bool" },
          { name: "settled", type: "bool" },
          { name: "failed", type: "bool" },
          { name: "totalCommitted", type: "uint256" },
          { name: "clearingSqrtPriceX96", type: "uint160" },
        ],
      },
    ],
  },

  // --- writes ---
  {
    type: "function",
    name: "commit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "id", type: "bytes32" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "settle",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [],
  },
  {
    type: "function",
    name: "claim",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [],
  },
  {
    type: "function",
    name: "refund",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [],
  },
] as const;
