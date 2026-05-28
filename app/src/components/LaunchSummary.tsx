"use client";

import type { Launch, Phase, PoolId } from "sealed-launch-sdk";

import { fmtAmount, fmtCountdown, fmtTimestamp } from "@/lib/format";

function PhaseChip({ phase }: { phase: Phase }) {
  return <span className={`phase ${phase}`}>{phase.replace("-", " ")}</span>;
}

function Row({
  k,
  v,
  mono = false,
}: {
  k: string;
  v: React.ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="row">
      <span className="k">{k}</span>
      <span className={`v ${mono ? "mono" : ""}`}>{v}</span>
    </div>
  );
}

export function LaunchSummary({
  launch,
  phase,
  now,
  launchAddr,
  poolId,
}: {
  launch: Launch;
  phase: Phase;
  now: bigint;
  launchAddr: string;
  poolId: PoolId;
}) {
  const oklink = (a: string) => `https://www.oklink.com/xlayer/address/${a}`;

  return (
    <div className="card">
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: 14,
        }}
      >
        <h2>Auction</h2>
        <PhaseChip phase={phase} />
      </div>

      <Row
        k="Manager"
        v={
          <a
            className="mono"
            href={oklink(launchAddr)}
            target="_blank"
            rel="noreferrer"
          >
            {launchAddr}
          </a>
        }
      />
      <Row k="Pool id" v={<span className="mono">{poolId}</span>} mono />
      <Row
        k="Token"
        v={
          <a
            className="mono"
            href={oklink(launch.token)}
            target="_blank"
            rel="noreferrer"
          >
            {launch.token}
          </a>
        }
      />
      <Row
        k="Quote"
        v={
          <a
            className="mono"
            href={oklink(launch.quote)}
            target="_blank"
            rel="noreferrer"
          >
            {launch.quote}
          </a>
        }
      />
      <Row k="Offered" v={fmtAmount(launch.offeredTokens)} />
      <Row k="LP seed" v={fmtAmount(launch.lpTokens)} />
      <Row
        k="Min raise"
        v={launch.minRaise === 0n ? "none" : fmtAmount(launch.minRaise)}
      />
      <Row k="Total revealed" v={fmtAmount(launch.totalRevealed)} />

      <Row
        k="Commit ends"
        v={
          <>
            {fmtTimestamp(launch.commitEnd)}
            {phase === "commit" && (
              <span className="muted">
                {" "}
                · in {fmtCountdown(launch.commitEnd, now)}
              </span>
            )}
          </>
        }
      />
      <Row
        k="Reveal ends"
        v={
          <>
            {fmtTimestamp(launch.revealEnd)}
            {phase === "reveal" && (
              <span className="muted">
                {" "}
                · in {fmtCountdown(launch.revealEnd, now)}
              </span>
            )}
          </>
        }
      />
      <Row
        k="Settled"
        v={launch.settled ? <span className="ok">yes</span> : "no"}
      />
      {launch.failed && (
        <Row
          k="Status"
          v={<span className="err">failed (refunds open)</span>}
        />
      )}
    </div>
  );
}
