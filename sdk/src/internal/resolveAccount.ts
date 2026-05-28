import type { Account, Address, Chain, WalletClient } from "viem";

/**
 * Shared write-context shape both v1 and v2 helpers use. Kept here so the
 * private helpers below can be reused without dragging a public type along.
 */
interface WriteCtxLike {
  wallet: WalletClient;
  account?: Account | Address;
}

/**
 * Resolve the signing account: prefer an explicit `ctx.account`, fall back to
 * one bound on the `WalletClient`. Throws if neither is available so callers
 * never silently fire a tx from `undefined`.
 */
export function resolveAccount(ctx: WriteCtxLike): Account | Address {
  const a = ctx.account ?? ctx.wallet.account;
  if (!a) {
    throw new Error(
      "[sealed-launch-sdk] No account: pass `account` or use a WalletClient created with `account: ...`.",
    );
  }
  return a;
}

/**
 * Resolve the chain to broadcast against. Viem treats `chain: null` as
 * "broadcast wherever the wallet currently is" — for a value-bearing launch
 * SDK that's a real-money footgun (e.g. signing a mainnet tx against a wallet
 * accidentally on a testnet). We require an explicit chain on the
 * `WalletClient` and surface a clear error if it's missing.
 */
export function resolveChain(ctx: WriteCtxLike): Chain {
  const chain = ctx.wallet.chain;
  if (!chain) {
    throw new Error(
      "[sealed-launch-sdk] No chain: create the WalletClient with `chain: ...` so writes can't be broadcast to the wrong network.",
    );
  }
  return chain;
}
