# sealed-launch-sdk

TypeScript SDK for [Sealed Launch](https://github.com/Ridwannurudeen/liftoff) — an order-independent, uniform-price batch-auction launch hook for **Uniswap v4** on **X Layer**.

- **v2 — `CommitRevealLaunch`** (primary): hashed commit + masked deposit + reveal. Bid sizes hidden on-chain until reveal.
- **v1 — `SealedLaunch`**: order-independent uniform-price clearing; bid amounts visible on-chain.

Both deployments are live on X Layer mainnet against the official Uniswap v4 PoolManager — see [`addresses.ts`](./src/addresses.ts).

## Install

```bash
npm i sealed-launch-sdk viem
```

## Quickstart — bid in a v2 launch

```ts
import {
  COMMIT_REVEAL_LAUNCH_V2,
  commitmentFor,
  commit,
  deriveSalt,
  reveal,
  claim,
  getLaunch,
  phaseOf,
} from "sealed-launch-sdk";
import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const account = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`);
const transport = http("https://rpc.xlayer.tech");
const publicClient = createPublicClient({ transport });
const walletClient = createWalletClient({ account, transport });
const ctx = { wallet: walletClient, public: publicClient, launch: COMMIT_REVEAL_LAUNCH_V2 };

const poolId = "0x..." as `0x${string}`; // from createLaunch (returned to the launcher)

// 1. Commit a sealed bid — masked deposit hides the real size.
const salt = deriveSalt(`my-bid-${Date.now()}`); // for real bids, use crypto.getRandomValues
const amount = 700n * 10n ** 18n;
const masked = 1000n * 10n ** 18n;          // any upper bound >= amount
const commitment = commitmentFor({ amount, salt, bidder: account.address });
// (don't forget to approve the launch contract on the quote token first)
await commit(ctx, { poolId, commitment, masked });

// 2. ...wait for the commit window to close, then reveal.
await reveal(ctx, { poolId, amount, salt });

// 3. ...wait for the reveal window to close. Anyone can call settle.
//    await settle(ctx, { poolId });

// 4. Claim your pro-rata allocation.
await claim(ctx, { poolId });

// Optional — drive UI off the on-chain phase.
const launch = await getLaunch({ client: publicClient, launch: COMMIT_REVEAL_LAUNCH_V2, poolId });
console.log(phaseOf(launch, BigInt(Math.floor(Date.now() / 1000))));
```

## API

| | v2 (`CommitRevealLaunch`) | v1 (`SealedLaunch`) |
|---|---|---|
| Write | `createLaunch`, `commit`, `reveal`, `settle`, `claim`, `reclaim` | `commitV1`, `settleV1`, `claimV1`, `refundV1` |
| Read | `getLaunch`, `getBid`, `totalRevealed`, `clearingPrice`, `allocationOf`, `phaseOf` | `getLaunchV1`, `totalCommitted`, `clearingPriceV1` |
| Helpers | `commitmentFor`, `deriveSalt` | — |
| Shared | `isSettled` (reads the gating hook for any pool) | |

All write helpers take a `{ wallet, public, launch, account? }` context and return the tx hash. `createLaunch` additionally waits for the receipt and returns the `poolId` decoded from the `LaunchCreated` event.

ABIs are exported (`commitRevealLaunchAbi`, `sealedLaunchAbi`, `sealedLaunchHookAbi`) so consumers can drop down to raw `viem`/`wagmi` calls when they need to.

## `commitmentFor` byte-equivalence

The TS helper produces the exact same `bytes32` as the on-chain `commitmentFor`:

```ts
commitmentFor({ amount, salt, bidder }) === keccak256(abi.encode(uint256, bytes32, address))
```

Verified against the live v2 demo on X Layer mainnet — see [`broadcast/`](../broadcast) and the on-chain manager at `0xaeD6bd08CDBaD833312d6BCFd9F97954350F606e`.

## Scope (v0.1)

This release wraps the read + write surface of the deployed contracts. **Not** included yet (planned for Phase 2): a React hooks add-on (`@sealed-launch/react`), tx simulation helpers, and a launch-config builder UI. See [`../ROADMAP.md`](../ROADMAP.md).

## License

MIT.
