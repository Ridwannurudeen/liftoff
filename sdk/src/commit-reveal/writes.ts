import {
  decodeEventLog,
  type Account,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from "viem";

import { commitRevealLaunchAbi } from "../abi/commit-reveal.js";
import type { LaunchParams, PoolId } from "./types.js";

/**
 * Args every write helper needs:
 * - `wallet` is the viem wallet client that signs and broadcasts.
 * - `public` is the viem public client used for receipt waits + log parsing.
 *   (Wallet clients in viem don't expose `waitForTransactionReceipt` on every
 *   transport, so the SDK takes both rather than guess.)
 * - `account` is optional when the wallet client already has one bound.
 */
export interface WriteCtx {
  wallet: WalletClient;
  public: PublicClient;
  launch: Address;
  account?: Account | Address;
}

function resolveAccount(ctx: WriteCtx): Account | Address {
  const a = ctx.account ?? ctx.wallet.account;
  if (!a) {
    throw new Error(
      "[sealed-launch-sdk] No account: pass `account` or use a WalletClient created with `account: ...`.",
    );
  }
  return a;
}

export interface CreateLaunchResult {
  txHash: Hex;
  poolId: PoolId;
  token: Address;
}

/**
 * Deploy a new `LaunchToken`, configure the gating hook, and open the commit
 * window. Returns the tx hash plus the `poolId` and freshly-deployed token
 * address recovered from the `LaunchCreated` event in the receipt.
 */
export async function createLaunch(
  ctx: WriteCtx,
  params: LaunchParams,
): Promise<CreateLaunchResult> {
  const account = resolveAccount(ctx);
  const txHash = await ctx.wallet.writeContract({
    address: ctx.launch,
    abi: commitRevealLaunchAbi,
    functionName: "createLaunch",
    args: [
      {
        name: params.name,
        symbol: params.symbol,
        totalSupply: params.totalSupply,
        offeredTokens: params.offeredTokens,
        lpTokens: params.lpTokens,
        quote: params.quote,
        startTime: params.startTime,
        commitEnd: params.commitEnd,
        revealEnd: params.revealEnd,
        minRaise: params.minRaise,
        maxMaskedPerWallet: params.maxMaskedPerWallet,
        tickSpacing: params.tickSpacing,
      },
    ],
    account,
    chain: ctx.wallet.chain ?? null,
  });

  const receipt = await ctx.public.waitForTransactionReceipt({ hash: txHash });

  for (const log of receipt.logs) {
    if (log.address.toLowerCase() !== ctx.launch.toLowerCase()) continue;
    try {
      const decoded = decodeEventLog({
        abi: commitRevealLaunchAbi,
        data: log.data,
        topics: log.topics,
      });
      if (decoded.eventName === "LaunchCreated") {
        const args = decoded.args as { id: Hex; token: Address };
        return { txHash, poolId: args.id, token: args.token };
      }
    } catch {
      // Skip logs that don't decode under this ABI.
    }
  }

  throw new Error(
    "[sealed-launch-sdk] createLaunch: tx mined but LaunchCreated event not found in receipt",
  );
}

export interface CommitArgs {
  poolId: PoolId;
  commitment: Hex;
  masked: bigint;
}

/** Post a sealed commitment + escrow the masked deposit. One commit per wallet per launch. */
export async function commit(ctx: WriteCtx, args: CommitArgs): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: commitRevealLaunchAbi,
    functionName: "commit",
    args: [args.poolId, args.commitment, args.masked],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}

export interface RevealArgs {
  poolId: PoolId;
  /** Real bid; must satisfy `amount <= masked` from your commit. `0n` is a valid withdraw. */
  amount: bigint;
  salt: Hex;
}

/**
 * Open a sealed bid during the reveal window. Refunds the masked overage
 * (`masked - amount`) atomically. `amount = 0n` is a valid early withdraw.
 */
export async function reveal(ctx: WriteCtx, args: RevealArgs): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: commitRevealLaunchAbi,
    functionName: "reveal",
    args: [args.poolId, args.amount, args.salt],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}

/** Close the auction, seed the pool at the clearing price, and open trading. */
export async function settle(
  ctx: WriteCtx,
  args: { poolId: PoolId },
): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: commitRevealLaunchAbi,
    functionName: "settle",
    args: [args.poolId],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}

/** Claim your pro-rata allocation after a successful settlement. */
export async function claim(
  ctx: WriteCtx,
  args: { poolId: PoolId },
): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: commitRevealLaunchAbi,
    functionName: "claim",
    args: [args.poolId],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}

/**
 * Reclaim escrowed quote when you get no allocation: either you never revealed
 * after a successful settle, or the launch failed (`totalRevealed < minRaise`).
 */
export async function reclaim(
  ctx: WriteCtx,
  args: { poolId: PoolId },
): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: commitRevealLaunchAbi,
    functionName: "reclaim",
    args: [args.poolId],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}
