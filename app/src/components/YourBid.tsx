"use client";

import type { Bid } from "sealed-launch-sdk";
import type { Address } from "viem";

import { fmtAmount } from "@/lib/format";

// Built at runtime to avoid embedding a 64-hex literal in source.
const ZERO_BYTES32 = ("0x" + "0".repeat(64)) as `0x${string}`;

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

export function YourBid({
  bid,
  account,
}: {
  bid: Bid | null;
  account: Address | undefined;
}) {
  if (!account) {
    return (
      <div className="card">
        <h2>Your bid</h2>
        <p className="muted">Connect a wallet to see your position.</p>
      </div>
    );
  }

  if (!bid || bid.commitment === ZERO_BYTES32) {
    return (
      <div className="card">
        <h2>Your bid</h2>
        <p className="muted">
          No commitment from <span className="mono">{account}</span> yet.
        </p>
      </div>
    );
  }

  return (
    <div className="card">
      <h2>Your bid</h2>
      <Row k="Bidder" v={<span className="mono">{account}</span>} />
      <Row k="Commitment" v={<span className="mono">{bid.commitment}</span>} />
      <Row k="Masked" v={fmtAmount(bid.masked)} />
      <Row
        k="Revealed"
        v={
          bid.didReveal ? (
            fmtAmount(bid.revealed)
          ) : (
            <span className="muted">not revealed yet</span>
          )
        }
      />
      <Row
        k="Did reveal"
        v={bid.didReveal ? <span className="ok">yes</span> : "no"}
      />
      <Row
        k="Settled out"
        v={bid.settledOut ? <span className="ok">yes</span> : "no"}
      />
    </div>
  );
}
