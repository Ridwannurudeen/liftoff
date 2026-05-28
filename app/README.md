# sealed-launch-app

The reference dApp for [Sealed Launch](https://github.com/Ridwannurudeen/liftoff) — a Next.js client that drives a commit / reveal / settle / claim auction end-to-end against the live X Layer (chain 196) deployment.

Package: `sealed-launch-app` · v0.1.0 · private (not published to npm).

## What it is

A thin viewer + write client built directly on top of [`sealed-launch-sdk`](../sdk). Three surfaces:

- **`/` — lifecycle viewer.** Reads any `CommitRevealLaunch` manager + pool id, derives the phase from `Launch` + chain time, and renders the right action verb for the current phase.
- **`/create` — deploy-your-own-auction.** Single transaction: mints a fresh ERC-20 and opens a CommitRevealLaunch pool via `createLaunch`.
- **dUSD2 faucet.** Inline mint card for the demo quote token so a visitor with zero balance can drive the demo without leaving the page.

There is no backend, no indexer, no database. Every screen is an on-chain read against `https://rpc.xlayer.tech`.

## Live

- Viewer — <https://sealedlaunch.gudman.xyz/app>
- Create — <https://sealedlaunch.gudman.xyz/app/create>

The viewer accepts `?launch=<addr>&poolId=<bytes32>` deep links; both params are validated (`isAddress`, `/^0x[0-9a-fA-F]{64}$/`) before they replace the demo defaults.

Default demo wired into the viewer (imported from the SDK):

- v2 manager (`COMMIT_REVEAL_LAUNCH_V2`): `0xaeD6bd08CDBaD833312d6BCFd9F97954350F606e`
- demo pool id: `0x33bd0be4…686cca`

## Stack

Next.js 15 (App Router) · React 19 · wagmi 2 · viem 2 · TanStack Query 5 · TypeScript strict. No Tailwind — palette via plain CSS vars in `globals.css`. Mounted at `/app` via `basePath: "/app"` + matching `assetPrefix` in `next.config.mjs` so it sits next to the existing static landing without colliding.

## Architecture

```
app/
  next.config.mjs              basePath + assetPrefix = /app
  public/manifest.webmanifest  PWA, scope = /app
  src/app/
    layout.tsx                 metadata (OG, Twitter, manifest, icons), viewport
    providers.tsx              wagmi + QueryClient
    page.tsx                   lifecycle viewer, KNOWN_LAUNCHES allowlist
    icon.svg                   favicon / app icon
    create/page.tsx            createLaunch form
  src/components/
    ActionPanel.tsx            commit / reveal / settle / claim / reclaim
    LaunchSummary.tsx          phase, timing, totals
    YourBid.tsx                bidder-specific state
    QuoteFaucet.tsx            dUSD2 mint card
    ConnectButton.tsx          wagmi connect + chain switch
  src/lib/
    wagmi.ts                   injected connector, xLayer transport
    chain.ts                   X_LAYER_RPC_URL, xLayer chain object
    useLaunch.ts               read hook + fetchBid helper
    saltStore.ts               localStorage salt cache
    walletNetwork.ts           ensureXLayerNetwork + error sanitizer
    format.ts                  amount / countdown formatters
```

## Run locally

The SDK is consumed via `file:../sdk`, so it must be built first:

```sh
cd liftoff/sdk && npm install && npm run build
cd ../app && npm install && npm run dev
# open http://localhost:3000/app
```

Re-run the SDK build (and `npm install` here) whenever `sdk/src` changes.

## Scripts

| Script | What it does |
| --- | --- |
| `npm run dev` | Next dev server on port 3000 |
| `npm run build` | `next build` — production bundle |
| `npm run start` | `next start` — serve the production bundle |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run lint` | `next lint` |

A clean `next build` emits four routes — `/`, `/create`, `/icon.svg`, `/_not-found`. The main viewer route comes out to roughly 96 kB / 216 kB First Load.

## Configuration

There is no `.env` for v0.1. Everything is on-chain reads, the RPC URL is hardcoded in `src/lib/chain.ts` (`https://rpc.xlayer.tech`, chain id 196), and contract addresses are imported from the SDK. The site URL used in metadata (`metadataBase`, OG `url`, canonical) is hardcoded to `https://sealedlaunch.gudman.xyz` in `src/app/layout.tsx`.

## Deploy

`npm run build && npm run start` produces a standard Next.js production server. The live site runs it as a `systemd` unit on a VPS, fronted by nginx, which serves the static landing at `/` and proxies `/app` to this Next server. There is no CI/CD wired up; deploys are manual.

## Security features

Each of these is a tightening from the FE audit pass:

- **Allowlisted launch managers.** `KNOWN_LAUNCHES = { COMMIT_REVEAL_LAUNCH_V2, SEALED_LAUNCH_V1 }`. Any other `?launch=` value renders a red warning bar; `ActionPanel` is rendered in a disabled, read-only state and refuses to broadcast any write until the user clicks "I understand this is an unverified contract." The same warning is mirrored in `/create` so a phishing pre-fill can't quietly retarget `createLaunch`.
- **Chain-id pinning.** `QuoteFaucet` and `/create` read with `usePublicClient({ chainId: 196 })`. All writes pass `chain: xLayer` (or the wallet's signed chain) explicitly so viem refuses to broadcast if the wallet drifts to another network. `ActionPanel` also early-returns if `useChainId()` isn't 196 before exposing any verb.
- **Provider-aware chain switch.** `ensureXLayerNetwork(provider)` (`src/lib/walletNetwork.ts`) takes the provider returned by the wagmi *connector* — `await connections[0].connector.getProvider()` — instead of reaching for `window.ethereum`. In an EIP-6963 multi-wallet browser the global injected provider is whichever extension won the race, not necessarily the one wagmi connected to.
- **Rabby-only runbook.** The "remove the stale RPC and re-add chain ID 0xc4" runbook only fires when `provider.isRabby === true`. Other wallets get a generic message; transient RPC throttles don't get misdiagnosed as wallet config.
- **Multi-tab commit race protection.** Right before broadcasting a commit, `CommitForm` re-reads the bid via `fetchBid(...)` and refuses if `bid.commitment !== ZERO_BYTES32`. Stops the second tab from burning gas on a sure revert.
- **Salt cache validation.** The salt cache lives in `localStorage` under `sealed-launch-sdk:salt:{launch}:{poolId}:{bidder}` (all lowercased). `loadValidatedSalt` rejects anything that fails `/^0x[0-9a-fA-F]{64}$/` for the salt or `typeof amount !== "bigint" || amount < 0n`, defending against a same-origin script poisoning the entry.
- **Faucet caps.** dUSD2 mint hard-capped at 100,000 per click, with a 3-second post-mint cooldown so the button can't be spam-clicked at the RPC.
- **Buttons disabled while pending.** Every write button switches to a `pending` label and `disabled` while a tx is in flight — no double-submits.
- **Sanitized error UI.** Viem `BaseError`s collapse to `shortMessage`; the raw chain payload is tucked inside a `<details>` so a malicious revert reason can't dominate the UI.

## Brand assets

Favicon and app icon: `src/app/icon.svg` (served at `/app/icon.svg`). PWA manifest: `public/manifest.webmanifest` (scope and `start_url` both `/app`). OG / Twitter card images are referenced from `layout.tsx` at `/og-image.svg` (served by the static landing at the site root). Theme color `#06070d`; Twitter handle `@sealedlaunch`; `metadataBase = https://sealedlaunch.gudman.xyz`.

## Known limitations

- Injected connector only. No WalletConnect, no Coinbase Wallet SDK.
- Not deeply tested on mobile; layout works, wallet flows depend on the mobile wallet's in-app browser.
- The OG / Twitter card image is SVG. Twitter, Discord, Telegram, and Slack render it; a few older preview bots prefer raster.
- No launch discovery / indexer. You bring the launch + pool id (deep link or default demo).
- No tests in this package; manual QA against the live deployment.

## Related

- Repo root: [`../README.md`](../README.md)
- SDK package: [`../sdk/README.md`](../sdk/README.md)

## License

MIT.
