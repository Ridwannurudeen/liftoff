"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { parseUnits, type Address, type Hex } from "viem";
import { useAccount, usePublicClient, useWalletClient } from "wagmi";

import { fmtAmount } from "@/lib/format";

const DUSD2 = "0x632bdC371EF86b9238dE795aEE2babABE3A5A277" as `0x${string}`;
const OKLINK_ADDR = `https://www.oklink.com/xlayer/address/${DUSD2}`;

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

function errMsg(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (typeof e === "string") return e;
  return "Unknown error";
}

function shortAddr(a: Address): string {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export default function QuoteFaucet() {
  const { address } = useAccount();
  const publicClient = usePublicClient({ chainId: 196 });
  const { data: walletClient } = useWalletClient();

  const [amountStr, setAmountStr] = useState("1000");
  const [status, setStatus] = useState<Status>({ kind: "idle" });

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

  const onMint = async () => {
    try {
      if (!walletClient) throw new Error("wallet not ready");
      if (!publicClient) throw new Error("rpc not ready");
      const amount = parseUnits(amountStr || "0", 18);
      if (amount <= 0n) throw new Error("amount must be > 0");

      setStatus({ kind: "pending", msg: "Minting dUSD2…" });
      const hash = await walletClient.writeContract({
        address: DUSD2,
        abi: dUSD2Abi,
        functionName: "mint",
        args: [address, amount],
        chain: walletClient.chain ?? null,
        account: address,
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setStatus({ kind: "ok", msg: "Minted.", tx: hash });
      await balanceQuery.refetch();
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: errMsg(e) });
    }
  };

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
        <label>Amount to mint</label>
        <input
          className="input"
          inputMode="decimal"
          value={amountStr}
          onChange={(e) => setAmountStr(e.target.value)}
        />
      </div>

      <div className="actions">
        <button
          className="btn"
          onClick={onMint}
          disabled={status.kind === "pending"}
        >
          Mint dUSD2
        </button>
      </div>

      <StatusLine status={status} />
    </div>
  );
}
