"use client";

import type { Address, Hex } from "viem";

/**
 * Local browser cache for bid salts so the user can reveal later from the
 * same browser. Not a real wallet — losing the salt loses the ability to
 * reveal (the on-chain commitment is just the hash). For production a user
 * would persist this themselves.
 */
const STORAGE_PREFIX = "sealed-launch-sdk:salt:";

function key(launch: Address, poolId: Hex, bidder: Address) {
  return `${STORAGE_PREFIX}${launch.toLowerCase()}:${poolId.toLowerCase()}:${bidder.toLowerCase()}`;
}

export function loadSalt(
  launch: Address,
  poolId: Hex,
  bidder: Address,
): { salt: Hex; amount: bigint } | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(key(launch, poolId, bidder));
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as { salt: string; amount: string };
    return { salt: parsed.salt as Hex, amount: BigInt(parsed.amount) };
  } catch {
    return null;
  }
}

export function saveSalt(
  launch: Address,
  poolId: Hex,
  bidder: Address,
  salt: Hex,
  amount: bigint,
): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(
    key(launch, poolId, bidder),
    JSON.stringify({ salt, amount: amount.toString() }),
  );
}

export function clearSalt(launch: Address, poolId: Hex, bidder: Address): void {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(key(launch, poolId, bidder));
}
