# X post (draft — do NOT post without approval)

## Option A — single post
Introducing Sealed Launch: a fair-launch @Uniswap v4 hook on @XLayerOfficial where being first buys you nothing.

Tokens launch via a sealed, uniform-price batch auction — no trading until it clears, then everyone settles at ONE price, pro-rata. Snipers and gas wars: irrelevant.

Built for @flapdotsh · liftoff.gudman.xyz
#XLayer #UniswapV4

[attach: 30–60s demo clip]

## Option B — short thread
1/ Every token launch gets sniped on block one. Fee decay, Dutch auctions, fixed-price windows — they all still reward whoever's fastest or best-connected.

Sealed Launch makes ordering *irrelevant*. A @Uniswap v4 hook on @XLayerOfficial. 🧵

2/ During the launch window the hook blocks every swap — nobody can trade the token before it clears. Buyers just commit. Commit order, block position, gas paid: none of it changes your outcome.

3/ At close, everyone clears at ONE uniform price, pro-rata:
`allocation = offered × yourCommit / totalCommit`
A first-block buyer and a last-block buyer get the identical price and allocation — and we prove it in the test suite.

4/ Why @XLayerOfficial specifically? It runs an OP-Stack flashblocks sequencer — we checked real blocks: txs aren't ordered by priority fee, so you can't out-order anyone. Instead of fighting ordering, Sealed Launch makes it not matter. Provably un-snipeable.

5/ Live on X Layer mainnet against the official @Uniswap v4 PoolManager — a real auction already settled on-chain.
Repo: github.com/Ridwannurudeen/liftoff
Live: liftoff.gudman.xyz
Hook: oklink.com/xlayer/address/0x594B539591e51e7981b05126B7e4d869C3BaA880
Demo: [VIDEO URL]
#XLayer #UniswapV4

## Notes
- Fill `[VIDEO URL]` before posting; Option A may run over the classic 280-char limit — trim or post as a long-form/premium post.
- Must tag **@XLayerOfficial, @Uniswap, @flapdotsh** (hackathon requirement). flap is a hackathon co-initiator — Sealed Launch is directly adoptable as its fair-launch mode (it has no anti-snipe today).
- Lead with the demo clip: commit (2+ wallets) → settle at one uniform price → live trading opens.
- v1 was "Liftoff" (fee-decay + caps); this post leads with Sealed Launch, the order-independent batch-auction model that supersedes it.
