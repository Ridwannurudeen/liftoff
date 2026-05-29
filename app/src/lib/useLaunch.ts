"use client";

import { useQuery } from "@tanstack/react-query";
import {
  commitRevealLaunchAbi,
  type Bid,
  type Launch,
  type PoolId,
} from "sealed-launch-sdk";
import type { Address, PublicClient } from "viem";
import { usePublicClient } from "wagmi";

/** Refetch the (launch, bid) tuple every 5s while the auction is live. */
export function useLaunch(args: {
  launch: Address | undefined;
  poolId: PoolId | undefined;
  user: Address | undefined;
}) {
  // Pin to chainId 196 so SSR + cold mounts never see an undefined client.
  const publicClient = usePublicClient({ chainId: 196 });

  return useQuery({
    queryKey: ["launch", args.launch, args.poolId, args.user],
    enabled: Boolean(publicClient && args.launch && args.poolId),
    refetchInterval: 5_000,
    // Refetch when the user switches tabs back so a commit/reveal that
    // happened in another tab is reflected before they click again.
    refetchOnWindowFocus: true,
    queryFn: async (): Promise<{ launch: Launch; bid: Bid | null }> => {
      if (!publicClient || !args.launch || !args.poolId) {
        throw new Error("missing args");
      }
      const [launch, bid] = await Promise.all([
        publicClient.readContract({
          address: args.launch,
          abi: commitRevealLaunchAbi,
          functionName: "getLaunch",
          args: [args.poolId],
        }) as Promise<Launch>,
        args.user
          ? (publicClient.readContract({
              address: args.launch,
              abi: commitRevealLaunchAbi,
              functionName: "getBid",
              args: [args.poolId, args.user],
            }) as Promise<Bid>)
          : Promise.resolve(null),
      ]);
      // Solidity returns a zero-initialized struct (token == address(0))
      // when the poolId doesn't exist on this manager. Treat that as "not
      // found" so the existing sanitized error UI engages instead of
      // rendering phantom auction cards.
      if (launch.token === "0x0000000000000000000000000000000000000000") {
        throw new Error(
          `No launch found for this manager + poolId. Double-check the pool id.`,
        );
      }
      return { launch, bid };
    },
  });
}

/**
 * One-shot fetch of just the bid for `(launch, poolId, user)`. Used to
 * defeat multi-tab desync: callers run this immediately before broadcasting
 * a commit/reveal to confirm the on-chain state still matches what the UI
 * is showing.
 */
export async function fetchBid(args: {
  publicClient: PublicClient;
  launch: Address;
  poolId: PoolId;
  user: Address;
}): Promise<Bid> {
  return (await args.publicClient.readContract({
    address: args.launch,
    abi: commitRevealLaunchAbi,
    functionName: "getBid",
    args: [args.poolId, args.user],
  })) as Bid;
}
