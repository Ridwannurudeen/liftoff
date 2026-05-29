"use client";

import { useState } from "react";
import {
  claim,
  commit,
  commitmentFor,
  deriveSalt,
  reclaim,
  reveal,
  settle,
  type Bid,
  type Launch,
  type Phase,
  type PoolId,
} from "sealed-launch-sdk";
import { erc20Abi, parseUnits, type Address, type Hex } from "viem";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useWalletClient,
} from "wagmi";

import { xLayer } from "@/lib/chain";
import { fmtAmount, fmtBigForInput, fmtCountdown } from "@/lib/format";
import { clearSalt, loadSalt, saveSalt } from "@/lib/saltStore";
import { fetchBid } from "@/lib/useLaunch";
import { walletErrorMessage } from "@/lib/walletNetwork";

interface ActionPanelProps {
  launch: Launch;
  bid: Bid | null;
  phase: Phase;
  now: bigint;
  launchAddr: Address;
  poolId: PoolId;
  refetch: () => void;
  /**
   * True when the launch manager is on the curated allowlist OR the user
   * has explicitly acknowledged the risk of interacting with an unverified
   * contract. When false, all action buttons are suppressed.
   */
  trusted: boolean;
}

type Status =
  | { kind: "idle" }
  | { kind: "pending"; msg: string }
  | { kind: "error"; msg: string }
  | { kind: "ok"; msg: string; tx?: Hex };

const SALT_RE = /^0x[0-9a-fA-F]{64}$/;
const ZERO_BYTES32 = ("0x" + "0".repeat(64)) as Hex;

/**
 * Defensive wrapper around `loadSalt`. The on-disk cache lives in
 * `localStorage` and is therefore writable by any same-origin script, so
 * validate the shape before consuming it.
 */
function loadValidatedSalt(
  launchAddr: Address,
  poolId: PoolId,
  bidder: Address,
): { salt: Hex; amount: bigint } | null {
  const cached = loadSalt(launchAddr, poolId, bidder);
  if (!cached) return null;
  if (typeof cached.salt !== "string" || !SALT_RE.test(cached.salt)) {
    console.warn("loadSalt: dropping entry with malformed salt");
    return null;
  }
  if (typeof cached.amount !== "bigint" || cached.amount < 0n) {
    console.warn("loadSalt: dropping entry with malformed amount");
    return null;
  }
  return cached;
}

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

export function ActionPanel({
  launch,
  bid,
  phase,
  now,
  launchAddr,
  poolId,
  refetch,
  trusted,
}: ActionPanelProps) {
  const { address } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient();
  // Pin to xLayer so the wallet client doesn't race during connection.
  const { data: walletClient } = useWalletClient({ chainId: xLayer.id });

  const [status, setStatus] = useState<Status>({ kind: "idle" });

  const writeCtx =
    walletClient && publicClient && address
      ? {
          wallet: walletClient,
          public: publicClient,
          launch: launchAddr,
          account: address,
        }
      : null;

  const hasCommit = bid !== null && bid.commitment !== ZERO_BYTES32;
  const didReveal = bid?.didReveal ?? false;
  const settledOut = bid?.settledOut ?? false;

  if (!address) {
    return (
      <div className="card">
        <h2>Actions</h2>
        <p className="muted">Connect a wallet to commit, reveal, or claim.</p>
      </div>
    );
  }

  if (chainId !== xLayer.id) {
    return (
      <div className="card">
        <h2>Actions</h2>
        <p className="muted">
          Switch your wallet to X Layer Mainnet before committing, revealing,
          settling, or claiming.
        </p>
      </div>
    );
  }

  // The page wraps an untrusted launch manager (off-allowlist + no user
  // ack) in read-only mode. Render the card but suppress every write path
  // so a phishing link can't trigger an ERC-20 approval against a hostile
  // contract.
  if (!trusted) {
    return (
      <div className="card">
        <h2>Actions</h2>
        <p className="muted">
          Actions are disabled until you acknowledge this is an unverified
          launch manager (see the warning at the top of the page).
        </p>
      </div>
    );
  }

  return (
    <div className="card">
      <h2>Actions</h2>

      {phase === "pending" && (
        <p className="muted">
          Auction opens in{" "}
          <span className="ok">{fmtCountdown(launch.startTime, now)}</span>.
        </p>
      )}

      {phase === "commit" && !hasCommit && writeCtx && (
        <CommitForm
          ctx={writeCtx}
          launch={launch}
          launchAddr={launchAddr}
          poolId={poolId}
          bidder={address}
          status={status}
          setStatus={setStatus}
          refetch={refetch}
        />
      )}
      {phase === "commit" && hasCommit && (
        <p className="muted">
          You&apos;ve already committed. Reveal opens at{" "}
          <span className="ok">{fmtCountdown(launch.commitEnd, now)}</span>.
        </p>
      )}

      {phase === "reveal" && hasCommit && !didReveal && writeCtx && (
        <RevealForm
          ctx={writeCtx}
          launchAddr={launchAddr}
          poolId={poolId}
          bidder={address}
          status={status}
          setStatus={setStatus}
          refetch={refetch}
        />
      )}
      {phase === "reveal" && !hasCommit && (
        <p className="muted">
          No commitment from this wallet — nothing to reveal.
        </p>
      )}
      {phase === "reveal" && hasCommit && didReveal && (
        <p className="muted">
          Revealed. Settle opens at{" "}
          <span className="ok">{fmtCountdown(launch.revealEnd, now)}</span>.
        </p>
      )}

      {phase === "awaiting-settle" && writeCtx && (
        <SettleButton
          ctx={writeCtx}
          poolId={poolId}
          status={status}
          setStatus={setStatus}
          refetch={refetch}
        />
      )}

      {phase === "settled" &&
        hasCommit &&
        !settledOut &&
        writeCtx &&
        didReveal && (
          <ClaimButton
            ctx={writeCtx}
            poolId={poolId}
            status={status}
            setStatus={setStatus}
            refetch={refetch}
          />
        )}
      {phase === "settled" &&
        hasCommit &&
        !settledOut &&
        writeCtx &&
        !didReveal && (
          <ReclaimButton
            ctx={writeCtx}
            poolId={poolId}
            status={status}
            setStatus={setStatus}
            refetch={refetch}
            label="Reclaim masked deposit (you didn't reveal)"
          />
        )}
      {phase === "settled" && settledOut && (
        <p className="ok">Your tokens / refund have already been collected.</p>
      )}
      {phase === "settled" && !hasCommit && (
        <p className="muted">Auction settled — no bid from this wallet.</p>
      )}

      {phase === "failed" && hasCommit && !settledOut && writeCtx && (
        <ReclaimButton
          ctx={writeCtx}
          poolId={poolId}
          status={status}
          setStatus={setStatus}
          refetch={refetch}
          label={didReveal ? "Reclaim revealed bid" : "Reclaim masked deposit"}
        />
      )}
      {phase === "failed" && (settledOut || !hasCommit) && (
        <p className="muted">Nothing to reclaim from this wallet.</p>
      )}

      <StatusLine status={status} />
    </div>
  );
}

// ---------------------------------------------------------------------------

type WriteCtxT = NonNullable<ReturnType<typeof useCtx>>;
function useCtx() {
  return null as unknown as Parameters<typeof commit>[0];
}

interface FormCommonProps {
  ctx: WriteCtxT;
  status: Status;
  setStatus: (s: Status) => void;
  refetch: () => void;
}

function CommitForm({
  ctx,
  launch,
  launchAddr,
  poolId,
  bidder,
  status,
  setStatus,
  refetch,
}: FormCommonProps & {
  launch: Launch;
  launchAddr: Address;
  poolId: PoolId;
  bidder: Address;
}) {
  const [amountStr, setAmountStr] = useState("");
  const [maskedStr, setMaskedStr] = useState("");
  const [saltStr, setSaltStr] = useState(
    `bid-${bidder.slice(2, 10)}-${Date.now()}`,
  );

  const pending = status.kind === "pending";

  const onCommit = async () => {
    try {
      const amount = parseUnits(amountStr || "0", 18);
      const masked = parseUnits(maskedStr || "0", 18);
      if (amount <= 0n) throw new Error("amount must be > 0");
      if (masked < amount) throw new Error("masked must be >= amount");
      if (
        launch.maxMaskedPerWallet !== 0n &&
        masked > launch.maxMaskedPerWallet
      ) {
        throw new Error(
          `masked exceeds per-wallet cap (${fmtAmount(launch.maxMaskedPerWallet)})`,
        );
      }

      const salt = deriveSalt(saltStr);
      const commitment = commitmentFor({ amount, salt, bidder });

      // Multi-tab desync defense: re-read the bid right before broadcast.
      // If another tab already committed for this wallet, refuse instead
      // of wasting gas on a sure-to-revert second commit.
      setStatus({
        kind: "pending",
        msg: "Confirming you haven't committed in another tab…",
      });
      const liveBid = await fetchBid({
        publicClient: ctx.public,
        launch: launchAddr,
        poolId,
        user: bidder,
      });
      if (liveBid.commitment !== ZERO_BYTES32) {
        throw new Error(
          "You already committed in another tab — refresh to see your bid.",
        );
      }

      // Approve the quote token if needed.
      setStatus({ kind: "pending", msg: "Approving quote token…" });
      const approveTx = await ctx.wallet.writeContract({
        address: launch.quote,
        abi: erc20Abi,
        functionName: "approve",
        args: [launchAddr, masked],
        account: ctx.account ?? bidder,
        chain: ctx.wallet.chain ?? null,
      });
      await ctx.public.waitForTransactionReceipt({ hash: approveTx });

      setStatus({ kind: "pending", msg: "Posting sealed commit…" });
      const tx = await commit(ctx, { poolId, commitment, masked });
      await ctx.public.waitForTransactionReceipt({ hash: tx });

      // Persist salt so we can reveal later.
      saveSalt(launchAddr, poolId, bidder, salt, amount);

      setStatus({ kind: "ok", msg: "Commit posted.", tx });
      refetch();
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: errMsg(e) });
    }
  };

  return (
    <>
      <div className="field">
        <label>Real bid amount (quote, decimals 18)</label>
        <input
          className="input"
          inputMode="decimal"
          placeholder="e.g. 700"
          value={amountStr}
          onChange={(e) => setAmountStr(e.target.value)}
        />
      </div>
      <div className="field">
        <label>Masked deposit (any upper bound &ge; amount)</label>
        <input
          className="input"
          inputMode="decimal"
          placeholder="e.g. 1000"
          value={maskedStr}
          onChange={(e) => setMaskedStr(e.target.value)}
        />
      </div>
      <div className="field">
        <label>Salt phrase (kept locally for reveal)</label>
        <input
          className="input"
          value={saltStr}
          onChange={(e) => setSaltStr(e.target.value)}
        />
      </div>
      <div className="actions">
        <button className="btn" onClick={onCommit} disabled={pending}>
          {pending ? "Submitting…" : "Approve & commit"}
        </button>
      </div>
    </>
  );
}

function RevealForm({
  ctx,
  launchAddr,
  poolId,
  bidder,
  status,
  setStatus,
  refetch,
}: FormCommonProps & {
  launchAddr: Address;
  poolId: PoolId;
  bidder: Address;
}) {
  const cached = loadValidatedSalt(launchAddr, poolId, bidder);
  const [amountStr, setAmountStr] = useState(
    cached ? fmtBigForInput(cached.amount) : "",
  );
  const [saltHex, setSaltHex] = useState<Hex | "">(cached?.salt ?? "");
  const [saltPhrase, setSaltPhrase] = useState("");

  const pending = status.kind === "pending";

  const onReveal = async () => {
    try {
      const amount = parseUnits(amountStr || "0", 18);
      const salt: Hex = saltHex || deriveSalt(saltPhrase);
      if (!salt || !SALT_RE.test(salt)) {
        throw new Error("provide a 32-byte salt (or the original phrase)");
      }

      setStatus({ kind: "pending", msg: "Revealing sealed bid…" });
      const tx = await reveal(ctx, { poolId, amount, salt });
      await ctx.public.waitForTransactionReceipt({ hash: tx });
      clearSalt(launchAddr, poolId, bidder);
      setStatus({ kind: "ok", msg: "Reveal posted.", tx });
      refetch();
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: errMsg(e) });
    }
  };

  return (
    <>
      <div className="field">
        <label>Bid amount (must match the original commit)</label>
        <input
          className="input"
          inputMode="decimal"
          placeholder="e.g. 700"
          value={amountStr}
          onChange={(e) => setAmountStr(e.target.value)}
        />
      </div>
      <div className="field">
        <label>Salt (bytes32 from local cache, or paste your own)</label>
        <input
          className="input mono"
          placeholder="0x… (32 bytes)"
          value={saltHex}
          onChange={(e) => setSaltHex(e.target.value as Hex | "")}
        />
      </div>
      <div className="field">
        <label>…or the original salt phrase used at commit</label>
        <input
          className="input"
          value={saltPhrase}
          onChange={(e) => setSaltPhrase(e.target.value)}
        />
      </div>
      <div className="actions">
        <button className="btn" onClick={onReveal} disabled={pending}>
          {pending ? "Submitting…" : "Reveal"}
        </button>
      </div>
    </>
  );
}

function SettleButton({
  ctx,
  poolId,
  status,
  setStatus,
  refetch,
}: FormCommonProps & { poolId: PoolId }) {
  const pending = status.kind === "pending";
  const onSettle = async () => {
    try {
      setStatus({ kind: "pending", msg: "Settling auction…" });
      const tx = await settle(ctx, { poolId });
      await ctx.public.waitForTransactionReceipt({ hash: tx });
      setStatus({ kind: "ok", msg: "Auction settled.", tx });
      refetch();
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: errMsg(e) });
    }
  };
  return (
    <div className="actions">
      <button className="btn" onClick={onSettle} disabled={pending}>
        {pending ? "Submitting…" : "Settle (anyone)"}
      </button>
    </div>
  );
}

function ClaimButton({
  ctx,
  poolId,
  status,
  setStatus,
  refetch,
}: FormCommonProps & { poolId: PoolId }) {
  const pending = status.kind === "pending";
  const onClaim = async () => {
    try {
      setStatus({ kind: "pending", msg: "Claiming allocation…" });
      const tx = await claim(ctx, { poolId });
      await ctx.public.waitForTransactionReceipt({ hash: tx });
      setStatus({ kind: "ok", msg: "Allocation claimed.", tx });
      refetch();
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: errMsg(e) });
    }
  };
  return (
    <div className="actions">
      <button className="btn" onClick={onClaim} disabled={pending}>
        {pending ? "Submitting…" : "Claim allocation"}
      </button>
    </div>
  );
}

function ReclaimButton({
  ctx,
  poolId,
  label,
  status,
  setStatus,
  refetch,
}: FormCommonProps & { poolId: PoolId; label: string }) {
  const pending = status.kind === "pending";
  const onReclaim = async () => {
    try {
      setStatus({ kind: "pending", msg: "Reclaiming escrow…" });
      const tx = await reclaim(ctx, { poolId });
      await ctx.public.waitForTransactionReceipt({ hash: tx });
      setStatus({ kind: "ok", msg: "Escrow reclaimed.", tx });
      refetch();
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: errMsg(e) });
    }
  };
  return (
    <div className="actions">
      <button className="btn" onClick={onReclaim} disabled={pending}>
        {pending ? "Submitting…" : label}
      </button>
    </div>
  );
}

function errMsg(e: unknown): string {
  return walletErrorMessage(e);
}
