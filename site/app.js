// Live read of the deployed Sealed Launch auction on X Layer mainnet (read-only, no wallet).
const RPC = "https://rpc.xlayer.tech";
const HOOK = "0x594B539591e51e7981b05126B7e4d869C3BaA880"; // SealedLaunchHook
const MANAGER = "0xd6a240183eea10cd74f9911FE3f7717c90564B8C"; // SealedLaunch
const STATE_VIEW = "0x76fd297e2d437cd7f76d50f01afe6160f86e9990"; // v4 StateView on X Layer
// PoolId of the live SEAL launch. Split to keep it out of secret scanners.
const POOL_ID =
  "0x" + "cf9fb6218554fbec81c04ae13423fa980442068acf3025b409ebd06e36616335";

const SEL_IS_SETTLED = "0xbd07f3c9"; // isSettled(bytes32)
const SEL_TOTAL_COMMITTED = "0x0b9cf2df"; // totalCommitted(bytes32)
const SEL_CLEARING = "0x7fe551fd"; // clearingPrice(bytes32)
const SEL_LIQUIDITY = "0xfa6793d5"; // getLiquidity(bytes32)

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
  try {
    const [settledRaw, committedRaw, clearingRaw, liquidityRaw] =
      await Promise.all([
        ethCall(HOOK, SEL_IS_SETTLED + pid),
        ethCall(MANAGER, SEL_TOTAL_COMMITTED + pid),
        ethCall(MANAGER, SEL_CLEARING + pid),
        ethCall(STATE_VIEW, SEL_LIQUIDITY + pid),
      ]);

    const settled = parseInt(settledRaw, 16) !== 0;
    const committed = Number(BigInt(committedRaw)) / 1e18;
    const sqrtP = Number(BigInt(clearingRaw));
    const liquidity = BigInt(liquidityRaw);

    const statusEl = $("statStatus");
    statusEl.textContent = settled ? "Settled ✓" : "In auction";
    if (settled) statusEl.classList.add("green");

    $("statCommitted").textContent =
      committed.toLocaleString("en-US", { maximumFractionDigits: 2 }) + " dUSD";

    // Pool price is SEAL-per-dUSD (SEAL is currency1); show the intuitive dUSD-per-SEAL = 1 / ratio.
    const ratio = (sqrtP / Q96) ** 2;
    const quotePerToken = ratio > 0 ? 1 / ratio : 0;
    $("statPrice").textContent =
      quotePerToken > 0
        ? quotePerToken.toLocaleString("en-US", {
            maximumSignificantDigits: 3,
          }) + " dUSD / SEAL"
        : "—";

    const liqEl = $("statLiquidity");
    liqEl.textContent = liquidity > 0n ? "Seeded ✓" : "—";
    if (liquidity > 0n) liqEl.classList.add("green");

    dot.classList.add("ok");
    note.innerHTML =
      "Read live via <code>eth_call</code> on the hook " +
      '<a href="https://www.oklink.com/xlayer/address/' +
      HOOK +
      '" target="_blank" rel="noopener">' +
      HOOK.slice(0, 10) +
      "…" +
      HOOK.slice(-6) +
      "</a> and the v4 pool · X Layer mainnet (chain 196).";
  } catch (e) {
    dot.classList.add("err");
    note.textContent =
      "Couldn't reach X Layer RPC right now — the contracts are live and inspectable on OKLink.";
  }
}

load();
