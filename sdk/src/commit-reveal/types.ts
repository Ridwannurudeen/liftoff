import type { Address, Hex } from "viem";

/** `bytes32` pool id returned from `createLaunch` and used by every other call. */
export type PoolId = Hex;

/**
 * Parameters for `CommitRevealLaunch.createLaunch`. Mirrors the on-chain
 * `LaunchParams` struct. Window invariant: `startTime < commitEnd < revealEnd`.
 */
export interface LaunchParams {
  name: string;
  symbol: string;
  totalSupply: bigint;
  /** Tokens distributed pro-rata at the clearing price. */
  offeredTokens: bigint;
  /** Tokens seeded into the pool at settlement. */
  lpTokens: bigint;
  /** ERC-20 used as the quote currency. */
  quote: Address;
  startTime: bigint;
  /** Last second of the commit window; reveals open at `commitEnd + 1`. */
  commitEnd: bigint;
  /** Last second of the reveal window; `settle()` becomes callable at `revealEnd + 1`. */
  revealEnd: bigint;
  /** Below this revealed total, the launch fails and bidders reclaim. */
  minRaise: bigint;
  /** Per-wallet cap on the masked deposit (and therefore the max bid). `0n` disables. */
  maxMaskedPerWallet: bigint;
  tickSpacing: number;
}

export interface Launch {
  token: Address;
  quote: Address;
  launcher: Address;
  totalSupply: bigint;
  offeredTokens: bigint;
  lpTokens: bigint;
  startTime: bigint;
  commitEnd: bigint;
  revealEnd: bigint;
  minRaise: bigint;
  maxMaskedPerWallet: bigint;
  tickSpacing: number;
  tokenIsCurrency0: boolean;
  settled: boolean;
  failed: boolean;
  totalRevealed: bigint;
  /** Q64.96 sqrt price the pool initialized at. `0n` until a successful settle. */
  clearingSqrtPriceX96: bigint;
}

export interface Bid {
  /** `keccak256(abi.encode(amount, salt, bidder))` — set on commit. */
  commitment: Hex;
  /** Upper-bound quote escrowed at commit time; overage is refunded at reveal. */
  masked: bigint;
  /** Real bid; `0n` until reveal. */
  revealed: bigint;
  didReveal: boolean;
  /** True after `claim` (success) or `reclaim` (failure / no-reveal). */
  settledOut: boolean;
}

export interface PoolKey {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}
