# sealed-launch-app

A small Next.js dApp that drives a [Sealed Launch](https://github.com/Ridwannurudeen/liftoff) auction end-to-end on X Layer mainnet — commit a sealed bid, reveal, settle, claim. Built on top of [`sealed-launch-sdk`](../sdk).

This is the canonical "what does the SDK actually look like in an app" reference. v0.1 ships:

- Wallet connect (injected) + chain-switch nudge to X Layer (chainId 196)
- Live read of any `CommitRevealLaunch` manager + pool id (defaults to the v2 mainnet demo)
- Phase indicator: `pending` → `commit` → `reveal` → `awaiting-settle` → `settled` / `failed`, derived from the on-chain `Launch` struct + chain time
- Action panel that flips the right verb at the right time: approve+commit, reveal, settle, claim, reclaim
- Local-storage salt cache so a bidder can reveal later from the same browser

Out of scope for v0.1 (planned next): launch discovery (no indexer yet), the `createLaunch` flow, multi-launch lists, server-side rendering of public state.

## Run locally

```bash
cd app
npm install
npm run dev
# open http://localhost:3000
```

`sealed-launch-sdk` is consumed via `file:../sdk`, so a `npm install` from the
parent `sdk/` first is required (already in this repo's git history). Re-run
`npm install` here if the SDK changes.

## Deep link to a specific launch

```
http://localhost:3000/?launch=0xaed6BD08CDBaD833312d6BcFd9F97954350F606e&poolId=0x33bd0be4...
```

Both query params are validated as `address` / `bytes32` before they replace the demo defaults.

## Stack

- Next.js 15 (App Router) + React 19
- wagmi 2 + viem 2
- `@tanstack/react-query` (5s refetch on the launch state while live)
- TypeScript strict (no Tailwind — inherits the `site/` palette via plain CSS vars)

## License

MIT.
