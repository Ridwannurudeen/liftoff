import type { Address, Hex } from "viem";

export type PoolId = Hex;

/** v1 launch struct — note `endTime` (single window) and `totalCommitted` (vs v2's `totalRevealed`). */
export interface SealedLaunch {
  token: Address;
  quote: Address;
  launcher: Address;
  totalSupply: bigint;
  offeredTokens: bigint;
  lpTokens: bigint;
  startTime: bigint;
  endTime: bigint;
  minRaise: bigint;
  maxCommitPerWallet: bigint;
  tickSpacing: number;
  tokenIsCurrency0: boolean;
  settled: boolean;
  failed: boolean;
  totalCommitted: bigint;
  clearingSqrtPriceX96: bigint;
}
