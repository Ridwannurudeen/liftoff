# sealed-launch-sdk

TypeScript SDK for [Sealed Launch](../README.md) — an order-independent, uniform-price batch-auction launch hook for **Uniswap v4** on **X Layer**. See also the [demo app](../app/README.md).

## TL;DR

- Wraps two live X Layer mainnet contracts: **v2 `CommitRevealLaunch`** (size-sealed) and **v1 `SealedLaunch`** (uniform-price).
- `commitmentFor` verified byte-for-byte against the on-chain pure function on the live mainnet demo.
- Runtime: any environment that runs `viem ^2.21.0` (Node 18+, modern browsers, edge runtimes). ESM + CJS dual export, full `.d.ts` typings.
- Install: today via git URL / `npm pack`; npm registry publish lands post-v0.1.

## Install

Until `0.1.0` is published to npm, install directly from the GitHub repo:

```sh
# v0.1 ship path: build a tarball locally, then install it in your app.
git clone https://github.com/Ridwannurudeen/sealedlaunch.git
cd sealedlaunch/sdk && npm install && npm run build && npm pack
# then in your app:
npm i path/to/sealed-launch-sdk-0.1.0.tgz viem
```

Planned post-v0.1 (once published):

```sh
npm i sealed-launch-sdk viem   # soon
```

`viem ^2.21.0` is a peer dependency — install it alongside.

## Quickstart — bid in a v2 launch

```ts
import {
  COMMIT_REVEAL_LAUNCH_V2,
  commit,
  commitmentFor,
  deriveSalt,
  reveal,
  claim,
  type WriteCtx,
} from "sealed-launch-sdk";
import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { xLayer } from "viem/chains";

const account = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`);
const transport = http("https://rpc.xlayer.tech");
const publicClient = createPublicClient({ chain: xLayer, transport });
const walletClient = createWalletClient({ account, chain: xLayer, transport });

const ctx: WriteCtx = { wallet: walletClient, public: publicClient, launch: COMMIT_REVEAL_LAUNCH_V2 };
const poolId = "0x..." as `0x${string}`; // from createLaunch (returned to the launcher)

// 1. Commit a sealed bid — masked deposit hides the real size.
const salt = deriveSalt(`bid-${Date.now()}`);     // demos: deterministic; real bids: crypto.getRandomValues
const amount = 700n * 10n ** 18n;
const masked = 1000n * 10n ** 18n;                // any upper bound >= amount
const commitment = commitmentFor({ amount, salt, bidder: account.address });
await commit(ctx, { poolId, commitment, masked }); // approve the quote token to `launch` first

// 2. After commitEnd, open your bid.
await reveal(ctx, { poolId, amount, salt });

// 3. After revealEnd, anyone can call settle(ctx, { poolId }); then:
await claim(ctx, { poolId });
```

## API reference

All write helpers take a `WriteCtx = { wallet, public, launch, account? }` and return a tx hash (`Hex`). All read helpers take a `ReadArgs = { client, launch, poolId }` (some also take `user: Address`). ABIs are exported so consumers can drop down to raw `viem`/`wagmi` when they need to.

### v2 — `CommitRevealLaunch` (primary)

| Symbol | Kind | Description |
|---|---|---|
| `createLaunch(ctx, params)` | write | Deploy `LaunchToken`, wire the gating hook, open the commit window. Waits for the receipt and returns `CreateLaunchResult = { txHash, poolId, token, key }` decoded from the `LaunchCreated` event. |
| `commit(ctx, args)` | write | Post a sealed commitment + escrow the masked deposit. One commit per wallet per launch. |
| `reveal(ctx, args)` | write | Open a sealed bid during the reveal window. Refunds `masked - amount` atomically. `amount = 0n` is a valid early withdraw. |
| `settle(ctx, { poolId })` | write | Close the auction, seed the pool at the clearing price, open trading. |
| `claim(ctx, { poolId })` | write | Claim your pro-rata allocation after a successful settlement. |
| `reclaim(ctx, { poolId })` | write | Recover escrowed quote on a failed launch or a missed reveal. |
| `getLaunch({ client, launch, poolId })` | read | Full `Launch` struct (windows, totals, flags). |
| `getBid({ ..., user })` | read | One bidder's `Bid` (commitment, masked, revealed). |
| `totalRevealed({ ... })` | read | Sum of revealed amounts (quote-token wei). |
| `clearingPrice({ ... })` | read | Uniform clearing price after settle (0 before). |
| `allocationOf({ ..., user })` | read | A bidder's pro-rata allocation in launch-token wei. |
| `commitmentFor(input)` | helper | Pure function: compute the on-chain commitment hash off-chain. |
| `deriveSalt(input)` | helper | NFC-normalized `keccak256` salt — see below. |
| `hasCommitted(bid)` | helper | `false` iff `bid.commitment === ZERO_BYTES32`. Disambiguates "never committed" from "committed with 0". |
| `phaseOf(launch, now)` | helper | `"pending" \| "commit" \| "reveal" \| "awaiting-settle" \| "settled" \| "failed"` for UI gating. |

Exported types: `LaunchParams`, `Launch`, `Bid`, `PoolId`, `PoolKey`, `Phase`, `ReadArgs`, `WriteCtx`, `CreateLaunchResult`, `CommitArgs`, `RevealArgs`, `CommitmentInput`.

### v1 — `SealedLaunch` (thin wrappers, also live on mainnet)

| Symbol | Kind | Description |
|---|---|---|
| `commitV1(ctx, args)` | write | Post a commitment (amounts visible on-chain). |
| `settleV1(ctx, args)` | write | Close the auction and seed the pool. |
| `claimV1(ctx, args)` | write | Claim allocation after settle. |
| `refundV1(ctx, args)` | write | Refund on a failed launch. |
| `getLaunchV1({ ... })` | read | Full `SealedLaunch` struct. |
| `totalCommitted({ ... })` | read | Sum of committed quote-token wei. |
| `clearingPriceV1({ ... })` | read | Uniform clearing price after settle. |

Exported types: `SealedLaunch`, `PoolIdV1`, `ReadArgsV1`, `WriteCtxV1`.

### Shared

| Symbol | Kind | Description |
|---|---|---|
| `isSettled({ client, hook, poolId })` | read | Reads the shared `SealedLaunchHook` gating bit for any pool (works for v1 and v2). |

Also exported: `commitRevealLaunchAbi`, `sealedLaunchAbi`, `sealedLaunchHookAbi` and the address constants `COMMIT_REVEAL_LAUNCH_V2`, `SEALED_LAUNCH_V1`, `SEALED_LAUNCH_HOOK`, `X_LAYER_POOL_MANAGER`, `X_LAYER_MAINNET_ID`, `X_LAYER_CONTRACTS`.

## Why `resolveChain(ctx)` throws

Viem treats `chain: null` on a `WalletClient` as "broadcast wherever the wallet currently is". For a value-bearing launch SDK that's a real-money footgun — a wallet accidentally pointed at a testnet would happily sign what the user thought was a mainnet tx. Internal audit finding #4 closed this hole: every write helper calls `resolveChain(ctx)` and throws if `WalletClient.chain` is missing.

This was disclosed in the internal audit pass (see [`../README.md`](../README.md) for the full finding list); no external audit is claimed.

```ts
// FAILS — chain not set on the wallet.
const wallet = createWalletClient({ account, transport });
await commit({ wallet, public: pub, launch }, args);
// Error: [sealed-launch-sdk] No chain: create the WalletClient with `chain: ...`

// PASSES — chain is explicit.
const wallet = createWalletClient({ account, chain: xLayer, transport });
await commit({ wallet, public: pub, launch }, args);
```

## `commitmentFor` byte-equivalence

The TS helper produces the exact same `bytes32` as the on-chain pure function:

```solidity
keccak256(abi.encode(uint256 amount, bytes32 salt, address bidder))
```

Verified against the live v2 mainnet demo:

```ts
const salt    = deriveSalt("v2-demo-saltA");
const amount  = 700n * 10n ** 18n;
const bidder  = "0x53Dd6dF0F92c9d5f4275827B9D1aecb79619E793" as const;
commitmentFor({ amount, salt, bidder }); // 0x251b4580… (matches on-chain commitmentFor)
```

To verify locally, call the contract's `commitmentFor(amount, salt, bidder)` view against the same inputs and compare — they will be identical.

## NFC normalization in `deriveSalt`

`deriveSalt(input)` calls `input.normalize("NFC")` before hashing, so visually-identical strings from different IMEs, terminals, or OSes produce the same salt:

```ts
deriveSalt("café-bid") === deriveSalt("café-bid"); // true — NFC collapses both
deriveSalt("rocket-🚀");                                   // stable across macOS/Linux/Windows
```

For demos and tests this is enough. For real bids generate 32 random bytes (e.g. `crypto.getRandomValues(new Uint8Array(32))`) and store the salt off-chain — losing it is equivalent to losing your bid.

## Live X Layer mainnet preset

`X_LAYER_CONTRACTS` bundles every address you need for v0.1:

```ts
import { X_LAYER_CONTRACTS, getLaunch } from "sealed-launch-sdk";
import { createPublicClient, http } from "viem";
import { xLayer } from "viem/chains";

const client = createPublicClient({ chain: xLayer, transport: http() });
const launch = await getLaunch({
  client,
  launch: X_LAYER_CONTRACTS.v2,
  poolId: "0x..." as `0x${string}`,
});
```

`X_LAYER_CONTRACTS` resolves to `{ chainId: 196, poolManager, hook, v1, v2 }` — all addresses are EIP-55 mixed-case.

## Build / typecheck

```sh
npm run build      # tsup → dist/index.js (ESM), dist/index.cjs (CJS), dist/index.d.ts
npm run typecheck  # tsc --noEmit
npm run clean      # rimraf dist
```

Bundle sizes for v0.1.0: ~17 KB ESM, ~18 KB CJS, ~26 KB `.d.ts`. The published `files` field ships `dist/` and `README.md` only — no source, no tests.

## Scope (v0.1)

**In:** full read + write surface for the deployed v2 and v1 contracts, ABIs, address constants, commitment helpers, NFC-normalized salt derivation, phase derivation, X Layer mainnet preset.

**Out (planned):** a React hooks add-on (`@sealed-launch/react`), tx simulation helpers, a launch-config builder UI. See [`../ROADMAP.md`](../ROADMAP.md).

## Breaking changes from v0.0.x

- `WriteCtx.chain` (formerly `Chain | null`) is removed. `chain` is now read from `WalletClient.chain` and `resolveChain(ctx)` **throws** when it's missing. Migrate by passing `chain: ...` to `createWalletClient`.
- `createLaunch` now returns `CreateLaunchResult = { txHash, poolId, token, key }` — the `key: PoolKey` is new and is decoded from the `LaunchCreated` event for consumers that need to address the pool through `PoolManager` directly.
- `deriveSalt` now applies `String.prototype.normalize("NFC")` before hashing. If you stored a v0.0.x salt derived from a non-NFC string, recompute it.

## License

MIT.
