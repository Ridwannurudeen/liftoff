import type { Address, Hex, PublicClient } from "viem";

import { sealedLaunchHookAbi } from "../abi/hook.js";

/**
 * `true` once the auction has settled and the pool is open for normal trading.
 * Reads the same hook that gates both v1 and v2 pools.
 */
export async function isSettled(args: {
  client: PublicClient;
  /** The hook address — pass `SEALED_LAUNCH_HOOK` for the canonical mainnet hook. */
  hook: Address;
  poolId: Hex;
}): Promise<boolean> {
  return args.client.readContract({
    address: args.hook,
    abi: sealedLaunchHookAbi,
    functionName: "isSettled",
    args: [args.poolId],
  });
}
