import type { Address, PublicClient } from "viem";

import { sealedLaunchAbi } from "../abi/sealed-launch.js";
import type { PoolId, SealedLaunch } from "./types.js";

export interface ReadArgs {
  client: PublicClient;
  /** Address of the `SealedLaunch` (v1) manager — e.g. `SEALED_LAUNCH_V1`. */
  launch: Address;
  poolId: PoolId;
}

export async function getLaunchV1({
  client,
  launch,
  poolId,
}: ReadArgs): Promise<SealedLaunch> {
  const raw = await client.readContract({
    address: launch,
    abi: sealedLaunchAbi,
    functionName: "getLaunch",
    args: [poolId],
  });
  return raw as SealedLaunch;
}

export async function totalCommitted({
  client,
  launch,
  poolId,
}: ReadArgs): Promise<bigint> {
  return client.readContract({
    address: launch,
    abi: sealedLaunchAbi,
    functionName: "totalCommitted",
    args: [poolId],
  });
}

export async function clearingPriceV1({
  client,
  launch,
  poolId,
}: ReadArgs): Promise<bigint> {
  return client.readContract({
    address: launch,
    abi: sealedLaunchAbi,
    functionName: "clearingPrice",
    args: [poolId],
  });
}
