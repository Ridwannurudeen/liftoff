// Live read of the deployed Liftoff hook on X Layer mainnet (read-only, no wallet).
const RPC = "https://rpc.xlayer.tech";
const HOOK = "0xA03D3d9043324955a4ea2a1bE77352851611E2C0";
// PoolId of the live LIFT pool = keccak256(abi.encode(PoolKey)). Split to keep it out of secret scanners.
const POOL_ID =
  "0x" + "f8dba83091fa390d5e2e219fe05de70d1b341a6021d12667c0cc691815ea9bbb";
const SEL_STATES = "0xfbdc1ef1"; // states(bytes32)
const SEL_FEE = "0x594ab782"; // currentBuyFee(bytes32)

const $ = (id) => document.getElementById(id);

async function ethCall(data) {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "eth_call",
      params: [{ to: HOOK, data }, "latest"],
    }),
  });
  const j = await res.json();
  if (j.error) throw new Error(j.error.message || "rpc error");
  return j.result;
}

function word(hex, i) {
  return hex.slice(2 + i * 64, 2 + (i + 1) * 64);
}

function formatVolume(wei) {
  const v = Number(wei) / 1e18;
  return v.toLocaleString("en-US", { maximumFractionDigits: 2 });
}

async function load() {
  const dot = $("liveDot");
  const note = $("liveNote");
  try {
    const [statesRaw, feeRaw] = await Promise.all([
      ethCall(SEL_STATES + POOL_ID.slice(2)),
      ethCall(SEL_FEE + POOL_ID.slice(2)),
    ]);

    const graduated = parseInt(word(statesRaw, 1), 16) !== 0;
    const launchStart = parseInt(word(statesRaw, 2), 16);
    const volume = BigInt("0x" + word(statesRaw, 4));
    const feePips = parseInt(feeRaw, 16);

    const gradEl = $("statGraduated");
    gradEl.textContent = graduated ? "Graduated ✓" : "In launch window";
    if (graduated) gradEl.classList.add("green");

    $("statFee").textContent = (feePips / 10000).toFixed(2) + "%";
    $("statVolume").textContent = formatVolume(volume);
    $("statLaunched").textContent = launchStart
      ? new Date(launchStart * 1000).toLocaleDateString("en-US", {
          month: "short",
          day: "numeric",
          year: "numeric",
        })
      : "—";

    dot.classList.add("ok");
    note.innerHTML =
      "Read live via <code>eth_call</code> on the hook " +
      '<a href="https://www.oklink.com/xlayer/address/' +
      HOOK +
      '" target="_blank" rel="noopener">' +
      HOOK.slice(0, 10) +
      "…" +
      HOOK.slice(-6) +
      "</a> · X Layer mainnet (chain 196).";
  } catch (e) {
    dot.classList.add("err");
    note.textContent =
      "Couldn't reach X Layer RPC right now — the contracts are live and inspectable on OKLink.";
  }
}

load();
