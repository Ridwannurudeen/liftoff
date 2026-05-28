"use client";

import { useQuery } from "@tanstack/react-query";
import {
  commitRevealLaunchAbi,
  type Bid,
  type Launch,
  type PoolId,
} from "sealed-launch-sdk";
import type { Address } from "viem";
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
      return { launch, bid };
    },
  });
}
