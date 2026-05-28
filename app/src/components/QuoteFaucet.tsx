"use client";

import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { parseUnits, type Address, type Hex } from "viem";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useWalletClient,
} from "wagmi";

import { xLayer } from "@/lib/chain";
import { fmtAmount } from "@/lib/format";
import { walletErrorMessage } from "@/lib/walletNetwork";

const DUSD2 = "0x632bdC371EF86b9238dE795aEE2babABE3A5A277" as `0x${string}`;
const OKLINK_ADDR = `https://www.oklink.com/xlayer/address/${DUSD2}`;

// Hard cap per click to keep demo numbers credible and to prevent click-spam
// from drowning the X Layer RPC pool with mock-mint traffic.
const MAX_MINT_PER_CLICK = 100_000n * 10n ** 18n;
// Cooldown (ms) after a successful mint before the button re-enables.
const COOLDOWN_MS = 3_000;

const dUSD2Abi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
] as const;

type Status =
  | { kind: "idle" }
  | { kind: "pending"; msg: string }
  | { kind: "error"; msg: string }
  | { kind: "ok"; msg: string; tx?: Hex };

function StatusLine({ status }: { status: Status }) {
  if (status.kind === "idle") return null;
  if (status.kind === "pending")
    return <p className="notice warn">{status.msg}</p>;
  if (status.kind === "error")
    return <p className="notice err">{status.msg}</p>;
  return (
    <p className="notice ok">
      {status.msg}
      {status.tx && (
        <>
          {" · "}
          <a
            className="mono"
            href={`https://www.oklink.com/xlayer/tx/${status.tx}`}
            target="_blank"
            rel="noreferrer"
          >
            view tx
          </a>
        </>
      )}
    </p>
  );
}

function shortAddr(a: Address): string {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export default function QuoteFaucet() {
  const { address } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient({ chainId: 196 });
  const { data: walletClient } = useWalletClient();

  const [amountStr, setAmountStr] = useState("1000");
  const [status, setStatus] = useState<Status>({ kind: "idle" });
  const [cooldown, setCooldown] = useState(false);

  // Clear the post-mint cooldown after COOLDOWN_MS so a single tab can mint
  // again without a page refresh.
  useEffect(() => {
    if (!cooldown) return;
    const id = window.setTimeout(() => setCooldown(false), COOLDOWN_MS);
    return () => window.clearTimeout(id);
  }, [cooldown]);

  const balanceQuery = useQuery<bigint>({
    queryKey: ["dUSD2-balance", address],
    enabled: Boolean(address && publicClient),
    refetchInterval: 10_000,
    queryFn: async () => {
      if (!publicClient || !address) throw new Error("no client");
      return publicClient.readContract({
        address: DUSD2,
        abi: dUSD2Abi,
        functionName: "balanceOf",
        args: [address],
      });
    },
  });

  if (!address) {
    return (
      <div className="card">
        <h2>Faucet</h2>
        <p className="muted">Connect a wallet to mint dUSD2.</p>
      </div>
    );
  }

  // Mirror the ActionPanel chain-id gate: dUSD2 only exists on X Layer
  // (chain 196). On any other chain the `mint(address,uint256)` selector
  // (0x40c10f19) may collide with an unrelated contract, so refuse to
  // broadcast.
  if (chainId !== xLayer.id) {
    return (
      <div className="card">
        <h2>Faucet</h2>
        <p className="muted">
          Switch your wallet to X Layer Mainnet to mint dUSD2.
        </p>
      </div>
    );
  }

  const onMint = async () => {
    try {
      if (!walletClient) throw new Error("wallet not ready");
      if (!publicClient) throw new Error("rpc not ready");
      const amount = parseUnits(amountStr || "0", 18);
      if (amount <= 0n) throw new Error("amount must be > 0");
      if (amount > MAX_MINT_PER_CLICK) {
        throw new Error("max 100,000 dUSD2 per click");
      }

      setStatus({ kind: "pending", msg: "Minting dUSD2…" });
      const hash = await walletClient.writeContract({
        address: DUSD2,
        abi: dUSD2Abi,
        functionName: "mint",
        args: [address, amount],
        // Pin to xLayer — viem refuses to broadcast if the wallet is on a
        // different chain. Belt-and-braces with the chainId gate above.
        chain: xLayer,
        account: address,
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setStatus({ kind: "ok", msg: "Minted.", tx: hash });
      setCooldown(true);
      await balanceQuery.refetch();
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: walletErrorMessage(e) });
    }
  };

  const buttonDisabled = status.kind === "pending" || cooldown;

  return (
    <div className="card">
      <h2>Quote token (dUSD2)</h2>

      <div className="row">
        <span className="k">Token</span>
        <span className="v">
          <a
            className="mono"
            href={OKLINK_ADDR}
            target="_blank"
            rel="noreferrer"
          >
            {shortAddr(DUSD2)}
          </a>
        </span>
      </div>
      <div className="row">
        <span className="k">Your balance</span>
        <span className="v">{fmtAmount(balanceQuery.data, "dUSD2")}</span>
      </div>

      <div className="field" style={{ marginTop: 12 }}>
        <label>Amount to mint (max 100,000 per click)</label>
        <input
          className="input"
          inputMode="decimal"
          value={amountStr}
          onChange={(e) => setAmountStr(e.target.value)}
        />
      </div>

      <div className="actions">
        <button className="btn" onClick={onMint} disabled={buttonDisabled}>
          {status.kind === "pending"
            ? "Minting…"
            : cooldown
              ? "Cooling down…"
              : "Mint dUSD2"}
        </button>
      </div>

      <StatusLine status={status} />
    </div>
  );
}
