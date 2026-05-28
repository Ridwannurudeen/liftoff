import type { Account, Address, Hex, PublicClient, WalletClient } from "viem";

import { sealedLaunchAbi } from "../abi/sealed-launch.js";
import type { PoolId } from "./types.js";

export interface WriteCtxV1 {
  wallet: WalletClient;
  public: PublicClient;
  /** Address of the `SealedLaunch` (v1) manager — e.g. `SEALED_LAUNCH_V1`. */
  launch: Address;
  account?: Account | Address;
}

function resolveAccount(ctx: WriteCtxV1): Account | Address {
  const a = ctx.account ?? ctx.wallet.account;
  if (!a) {
    throw new Error(
      "[sealed-launch-sdk] No account: pass `account` or use a WalletClient created with `account: ...`.",
    );
  }
  return a;
}

/** Commit `amount` quote into a v1 launch. Bid amount is visible on-chain. */
export async function commitV1(
  ctx: WriteCtxV1,
  args: { poolId: PoolId; amount: bigint },
): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: sealedLaunchAbi,
    functionName: "commit",
    args: [args.poolId, args.amount],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}

export async function settleV1(
  ctx: WriteCtxV1,
  args: { poolId: PoolId },
): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: sealedLaunchAbi,
    functionName: "settle",
    args: [args.poolId],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}

export async function claimV1(
  ctx: WriteCtxV1,
  args: { poolId: PoolId },
): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: sealedLaunchAbi,
    functionName: "claim",
    args: [args.poolId],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}

export async function refundV1(
  ctx: WriteCtxV1,
  args: { poolId: PoolId },
): Promise<Hex> {
  const account = resolveAccount(ctx);
  return ctx.wallet.writeContract({
    address: ctx.launch,
    abi: sealedLaunchAbi,
    functionName: "refund",
    args: [args.poolId],
    account,
    chain: ctx.wallet.chain ?? null,
  });
}
