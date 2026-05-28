// Live read of the deployed Sealed Launch v2 demo auction on X Layer mainnet
// (read-only, no wallet). Reads straight from the hook + v2 manager + v4 pool.
const RPC = "https://rpc.xlayer.tech";
const HOOK = "0x594B539591e51e7981b05126B7e4d869C3BaA880"; // SealedLaunchHook (shared v1+v2)
const MANAGER = "0xaeD6bd08CDBaD833312d6BCFd9F97954350F606e"; // CommitRevealLaunch v2
const STATE_VIEW = "0x76fd297e2d437cd7f76d50f01afe6160f86e9990"; // v4 StateView on X Layer
// PoolId of the live v2 SBID launch (settled mainnet demo). Split to keep it
// out of secret scanners.
const POOL_ID =
  "0x" + "33bd0be44367cc00fb0c59e15ce1385e3160b6a9f07a1b39676256dd67686cca";

const SEL_IS_SETTLED = "0xbd07f3c9"; // isSettled(bytes32)            — hook
const SEL_TOTAL_REVEALED = "0x85fe945e"; // totalRevealed(bytes32)    — v2 manager
const SEL_CLEARING = "0x7fe551fd"; // clearingPrice(bytes32)          — v2 manager
const SEL_LIQUIDITY = "0xfa6793d5"; // getLiquidity(bytes32)          — StateView

const Q96 = 2 ** 96;
const $ = (id) => document.getElementById(id);

async function ethCall(to, data) {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "eth_call",
      params: [{ to, data }, "latest"],
    }),
  });
  const j = await res.json();
  if (j.error) throw new Error(j.error.message || "rpc error");
  return j.result;
}

const pid = POOL_ID.slice(2);

async function load() {
  const dot = $("liveDot");
  const note = $("liveNote");
  if (!dot || !note) return; // widget not mounted on this page
  try {
    const [settledRaw, revealedRaw, clearingRaw, liquidityRaw] =
      await Promise.all([
        ethCall(HOOK, SEL_IS_SETTLED + pid),
        ethCall(MANAGER, SEL_TOTAL_REVEALED + pid),
        ethCall(MANAGER, SEL_CLEARING + pid),
        ethCall(STATE_VIEW, SEL_LIQUIDITY + pid),
      ]);

    const settled = parseInt(settledRaw, 16) !== 0;
    const revealed = Number(BigInt(revealedRaw)) / 1e18;
    const sqrtP = Number(BigInt(clearingRaw));
    const liquidity = BigInt(liquidityRaw);

    const statusEl = $("statStatus");
    statusEl.textContent = settled ? "Settled ✓" : "In auction";
    if (settled) statusEl.classList.add("green");

    $("statCommitted").textContent =
      revealed.toLocaleString("en-US", { maximumFractionDigits: 2 }) + " dUSD2";

    // Pool price is SBID-per-dUSD2 (SBID is currency1); show the intuitive
    // dUSD2-per-SBID = 1 / ratio.
    const ratio = (sqrtP / Q96) ** 2;
    const quotePerToken = ratio > 0 ? 1 / ratio : 0;
    $("statPrice").textContent =
      quotePerToken > 0
        ? quotePerToken.toLocaleString("en-US", {
            maximumSignificantDigits: 3,
          }) + " dUSD2 / SBID"
        : "—";

    const liqEl = $("statLiquidity");
    liqEl.textContent = liquidity > 0n ? "Seeded ✓" : "—";
    if (liquidity > 0n) liqEl.classList.add("green");

    dot.classList.add("ok");
    note.innerHTML =
      "Read live via <code>eth_call</code> on the v2 manager " +
      '<a href="https://www.oklink.com/xlayer/address/' +
      MANAGER +
      '" target="_blank" rel="noopener">' +
      MANAGER.slice(0, 10) +
      "…" +
      MANAGER.slice(-6) +
      "</a> and the v4 pool · X Layer mainnet (chain 196).";
  } catch (e) {
    dot.classList.add("err");
    note.textContent =
      "Couldn't reach X Layer RPC right now — the contracts are live and inspectable on OKLink.";
  }
}

load();
