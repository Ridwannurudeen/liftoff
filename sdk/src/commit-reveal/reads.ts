import type { Address, PublicClient } from "viem";

import { commitRevealLaunchAbi } from "../abi/commit-reveal.js";
import type { Bid, Launch, PoolId } from "./types.js";

export interface ReadArgs {
  client: PublicClient;
  /** Address of the `CommitRevealLaunch` (e.g. mainnet v2 from `addresses.ts`). */
  launch: Address;
  poolId: PoolId;
}

export async function getLaunch({
  client,
  launch,
  poolId,
}: ReadArgs): Promise<Launch> {
  const raw = await client.readContract({
    address: launch,
    abi: commitRevealLaunchAbi,
    functionName: "getLaunch",
    args: [poolId],
  });
  return raw as Launch;
}

export async function getBid(args: ReadArgs & { user: Address }): Promise<Bid> {
  const { client, launch, poolId, user } = args;
  const raw = await client.readContract({
    address: launch,
    abi: commitRevealLaunchAbi,
    functionName: "getBid",
    args: [poolId, user],
  });
  return raw as Bid;
}

export async function totalRevealed({
  client,
  launch,
  poolId,
}: ReadArgs): Promise<bigint> {
  return client.readContract({
    address: launch,
    abi: commitRevealLaunchAbi,
    functionName: "totalRevealed",
    args: [poolId],
  });
}

export async function clearingPrice({
  client,
  launch,
  poolId,
}: ReadArgs): Promise<bigint> {
  return client.readContract({
    address: launch,
    abi: commitRevealLaunchAbi,
    functionName: "clearingPrice",
    args: [poolId],
  });
}

export async function allocationOf(
  args: ReadArgs & { user: Address },
): Promise<bigint> {
  const { client, launch, poolId, user } = args;
  return client.readContract({
    address: launch,
    abi: commitRevealLaunchAbi,
    functionName: "allocationOf",
    args: [poolId, user],
  });
}

/**
 * Derive the auction phase from the launch struct + current chain time.
 * Cheap, non-authoritative — for UI gating only. The contract enforces these
 * windows itself via reverts.
 */
export type Phase =
  | "pending"
  | "commit"
  | "reveal"
  | "awaiting-settle"
  | "settled"
  | "failed";

export function phaseOf(launch: Launch, now: bigint): Phase {
  if (launch.failed) return "failed";
  if (launch.settled) return "settled";
  if (now < launch.startTime) return "pending";
  if (now <= launch.commitEnd) return "commit";
  if (now <= launch.revealEnd) return "reveal";
  return "awaiting-settle";
}
