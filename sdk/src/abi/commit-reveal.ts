/**
 * ABI for `CommitRevealLaunch` (v2). Mirrors the deployed contract's external
 * surface verbatim — fields kept in source order to make tuple decoding
 * predictable when callers prefer positional access over named.
 */
export const commitRevealLaunchAbi = [
  // --- reads ---
  {
    type: "function",
    name: "commitmentFor",
    stateMutability: "pure",
    inputs: [
      { name: "amount", type: "uint256" },
      { name: "salt", type: "bytes32" },
      { name: "bidder", type: "address" },
    ],
    outputs: [{ name: "", type: "bytes32" }],
  },
  {
    type: "function",
    name: "totalRevealed",
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
    name: "allocationOf",
    stateMutability: "view",
    inputs: [
      { name: "id", type: "bytes32" },
      { name: "user", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
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
          { name: "commitEnd", type: "uint64" },
          { name: "revealEnd", type: "uint64" },
          { name: "minRaise", type: "uint256" },
          { name: "maxMaskedPerWallet", type: "uint256" },
          { name: "tickSpacing", type: "int24" },
          { name: "tokenIsCurrency0", type: "bool" },
          { name: "settled", type: "bool" },
          { name: "failed", type: "bool" },
          { name: "totalRevealed", type: "uint256" },
          { name: "clearingSqrtPriceX96", type: "uint160" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "getBid",
    stateMutability: "view",
    inputs: [
      { name: "id", type: "bytes32" },
      { name: "user", type: "address" },
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "commitment", type: "bytes32" },
          { name: "masked", type: "uint256" },
          { name: "revealed", type: "uint256" },
          { name: "didReveal", type: "bool" },
          { name: "settledOut", type: "bool" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "hook",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "poolManager",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "LP_FEE",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint24" }],
  },

  // --- writes ---
  {
    type: "function",
    name: "createLaunch",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "p",
        type: "tuple",
        components: [
          { name: "name", type: "string" },
          { name: "symbol", type: "string" },
          { name: "totalSupply", type: "uint256" },
          { name: "offeredTokens", type: "uint256" },
          { name: "lpTokens", type: "uint256" },
          { name: "quote", type: "address" },
          { name: "startTime", type: "uint64" },
          { name: "commitEnd", type: "uint64" },
          { name: "revealEnd", type: "uint64" },
          { name: "minRaise", type: "uint256" },
          { name: "maxMaskedPerWallet", type: "uint256" },
          { name: "tickSpacing", type: "int24" },
        ],
      },
    ],
    outputs: [
      { name: "token", type: "address" },
      {
        name: "key",
        type: "tuple",
        components: [
          { name: "currency0", type: "address" },
          { name: "currency1", type: "address" },
          { name: "fee", type: "uint24" },
          { name: "tickSpacing", type: "int24" },
          { name: "hooks", type: "address" },
        ],
      },
      { name: "id", type: "bytes32" },
    ],
  },
  {
    type: "function",
    name: "commit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "id", type: "bytes32" },
      { name: "commitment", type: "bytes32" },
      { name: "masked", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "reveal",
    stateMutability: "nonpayable",
    inputs: [
      { name: "id", type: "bytes32" },
      { name: "amount", type: "uint256" },
      { name: "salt", type: "bytes32" },
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
    name: "reclaim",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [],
  },

  // --- events (the SDK needs LaunchCreated to recover the poolId from createLaunch) ---
  {
    type: "event",
    name: "LaunchCreated",
    inputs: [
      { name: "id", type: "bytes32", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "launcher", type: "address", indexed: true },
      {
        name: "key",
        type: "tuple",
        indexed: false,
        components: [
          { name: "currency0", type: "address" },
          { name: "currency1", type: "address" },
          { name: "fee", type: "uint24" },
          { name: "tickSpacing", type: "int24" },
          { name: "hooks", type: "address" },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Committed",
    inputs: [
      { name: "id", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "masked", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Revealed",
    inputs: [
      { name: "id", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "refundedOverage", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Settled",
    inputs: [
      { name: "id", type: "bytes32", indexed: true },
      { name: "clearingSqrtPriceX96", type: "uint160", indexed: false },
      { name: "totalRevealed", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Claimed",
    inputs: [
      { name: "id", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "tokenAmount", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
] as const;
