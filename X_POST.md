# X post (draft — do NOT post without approval)

## Option A — single post
Sealed Launch is live on @XLayerOfficial: a @Uniswap v4 hook where token launches clear at ONE uniform price, pro-rata.

v1 makes block order irrelevant. v2 (deployed today) seals the bid sizes too — hashed commit + reveal. Two on-chain bidders settled live.

Built for @flapdotsh · liftoff.gudman.xyz
#XLayer #UniswapV4

[attach: 30–60s demo clip]

## Option B — short thread
1/ Token launches get sniped on block one. Every existing defense — fee decay, Dutch auctions, fixed-price windows — still rewards whoever's fastest or best-connected.

Sealed Launch makes ordering *irrelevant*. A @Uniswap v4 hook on @XLayerOfficial. 🧵

2/ During the launch window the hook blocks every swap — nobody trades the token before it clears. Buyers just commit. Commit order, block position, gas paid: none of it changes your outcome.

3/ At close, everyone clears at ONE uniform price, pro-rata:
`allocation = offered × yourCommit / totalCommit`
A first-block buyer and a last-block buyer get the identical price and allocation — and we prove it in the test suite.

4/ Why @XLayerOfficial specifically? It runs an OP-Stack flashblocks sequencer — we checked real blocks: txs aren't ordered by priority fee, so you can't out-order anyone. Instead of fighting ordering, Sealed Launch makes it not matter. Provably un-snipeable.

5/ v2 went live today: a sealed-bid commit-reveal mode. Bidders post `keccak256(amount, salt, bidder)` + a masked escrow during the commit window, then reveal the real amount later. Bid SIZES stay hidden on-chain until reveal — order-independent AND size-sealed.

6/ Both versions are settled on X Layer mainnet against the OFFICIAL @Uniswap v4 PoolManager. v1 cleared 1,000 dUSD into a fresh pool. v2 just settled two on-chain bidders (masked 1000+500 → revealed 700+300 → 280k/120k SBID claimed pro-rata → live post-settlement swap).
Repo: github.com/Ridwannurudeen/liftoff
Live: liftoff.gudman.xyz
v1 Hook: oklink.com/xlayer/address/0x594B539591e51e7981b05126B7e4d869C3BaA880
v2 Manager: oklink.com/xlayer/address/0xaeD6bd08CDBaD833312d6BCFd9F97954350F606e
Demo: [VIDEO URL]
#XLayer #UniswapV4

## Notes
- Fill `[VIDEO URL]` before posting; Option A may run over the classic 280-char limit — trim or post as a long-form/premium post.
- Must tag **@XLayerOfficial, @Uniswap, @flapdotsh** (hackathon requirement). flap is a hackathon co-initiator — Sealed Launch is directly adoptable as its fair-launch mode (it has no anti-snipe today).
- Lead the clip with the v2 demo: two on-chain commits (sealed sizes) → reveals (sizes appear) → settle at one uniform price → both bidders claim pro-rata → live trading opens.
- v1 was "Liftoff" (fee-decay + caps); the v1 *Sealed Launch* (order-independent) and v2 *CommitRevealLaunch* (size-sealed) supersede it.
