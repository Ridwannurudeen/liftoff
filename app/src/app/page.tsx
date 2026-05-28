"use client";

import { useEffect, useMemo, useState } from "react";
import {
  COMMIT_REVEAL_LAUNCH_V2,
  phaseOf,
  type PoolId,
} from "sealed-launch-sdk";
import { isAddress, isHex, type Address } from "viem";
import { useAccount } from "wagmi";

import { ActionPanel } from "@/components/ActionPanel";
import { ConnectButton } from "@/components/ConnectButton";
import { LaunchSummary } from "@/components/LaunchSummary";
import { YourBid } from "@/components/YourBid";
import { useLaunch } from "@/lib/useLaunch";

// Hardcoded fallback so the dApp is useful with zero query params: the v2
// mainnet demo. PoolId built from the broadcast log's first indexed topic
// (`LaunchCreated.id`) — see broadcast/DeployCommitRevealDemo.s.sol/196/.
const DEMO_LAUNCH = COMMIT_REVEAL_LAUNCH_V2;
const DEMO_POOL_ID = ("0x33bd0be4" +
  "4367cc00fb0c59e15ce1385e3160b6a9f07a1b39676256dd67686cca") as PoolId;

export default function Page() {
  const [launchAddr, setLaunchAddr] = useState<Address>(DEMO_LAUNCH);
  const [poolId, setPoolId] = useState<PoolId>(DEMO_POOL_ID);
  const [launchInput, setLaunchInput] = useState<string>(DEMO_LAUNCH);
  const [poolIdInput, setPoolIdInput] = useState<string>(DEMO_POOL_ID);

  // Hydrate from query params on mount so links like ?launch=…&poolId=… work.
  useEffect(() => {
    if (typeof window === "undefined") return;
    const sp = new URLSearchParams(window.location.search);
    const l = sp.get("launch");
    const p = sp.get("poolId");
    if (l && isAddress(l)) {
      setLaunchAddr(l as Address);
      setLaunchInput(l);
    }
    if (p && isHex(p) && p.length === 66) {
      setPoolId(p as PoolId);
      setPoolIdInput(p);
    }
  }, []);

  const { address } = useAccount();
  const { data, refetch, isLoading, error } = useLaunch({
    launch: launchAddr,
    poolId,
    user: address,
  });

  // Tick `now` once a second so countdown text actually counts down.
  const [now, setNow] = useState<bigint>(() =>
    BigInt(Math.floor(Date.now() / 1000)),
  );
  useEffect(() => {
    const id = window.setInterval(
      () => setNow(BigInt(Math.floor(Date.now() / 1000))),
      1000,
    );
    return () => window.clearInterval(id);
  }, []);

  const phase = useMemo(
    () => (data ? phaseOf(data.launch, now) : null),
    [data, now],
  );

  const onLoad = () => {
    if (isAddress(launchInput)) setLaunchAddr(launchInput as Address);
    if (isHex(poolIdInput) && poolIdInput.length === 66)
      setPoolId(poolIdInput as PoolId);
  };

  return (
    <main className="shell">
      <header className="nav">
        <a className="brand" href="https://liftoff.gudman.xyz">
          <span className="brand-mark">▲</span> Sealed Launch
        </a>
        <ConnectButton />
      </header>

      <section className="hero">
        <h1>Drive a sealed batch-auction launch — live on X Layer mainnet</h1>
        <p>
          Sealed Launch settles every token launch at one uniform clearing
          price. v1 is order-independent. v2 hides bid sizes via hashed commit +
          reveal. Both run on the{" "}
          <strong>official Uniswap v4 PoolManager</strong> on X Layer (chain
          196). Connect a wallet and drive the lifecycle below.
        </p>
      </section>

      <div className="card" style={{ marginTop: 28 }}>
        <h2>Live mainnet deployment</h2>
        <div className="row">
          <span className="k">v2 — CommitRevealLaunch</span>
          <a
            className="v mono"
            href={`https://www.oklink.com/xlayer/address/${DEMO_LAUNCH}`}
            target="_blank"
            rel="noreferrer"
          >
            {DEMO_LAUNCH}
          </a>
        </div>
        <div className="row">
          <span className="k">v1 — SealedLaunch (manager)</span>
          <a
            className="v mono"
            href="https://www.oklink.com/xlayer/address/0xd6a240183eea10cd74f9911FE3f7717c90564B8C"
            target="_blank"
            rel="noreferrer"
          >
            0xd6a240183eea10cd74f9911FE3f7717c90564B8C
          </a>
        </div>
        <div className="row">
          <span className="k">SealedLaunchHook (shared)</span>
          <a
            className="v mono"
            href="https://www.oklink.com/xlayer/address/0x594B539591e51e7981b05126B7e4d869C3BaA880"
            target="_blank"
            rel="noreferrer"
          >
            0x594B539591e51e7981b05126B7e4d869C3BaA880
          </a>
        </div>
        <div className="row">
          <span className="k">Official v4 PoolManager (X Layer)</span>
          <a
            className="v mono"
            href="https://www.oklink.com/xlayer/address/0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32"
            target="_blank"
            rel="noreferrer"
          >
            0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32
          </a>
        </div>
        <div className="row">
          <span className="k">Demo auction (v2)</span>
          <span className="v">
            settled · 1,000 dUSD2 cleared · 280k+120k SBID claimed pro-rata ·
            live swap proven
          </span>
        </div>
      </div>

      <div className="card" style={{ marginTop: 20 }}>
        <h2>How the auction works</h2>
        <ol style={{ paddingLeft: "20px", marginTop: 4 }}>
          <li className="muted" style={{ marginBottom: 6 }}>
            <strong>Commit window</strong> — bidders post a hashed commitment (
            <span className="mono">keccak256(amount, salt, bidder)</span>) and
            escrow a masked deposit. The pool is gated; nobody can trade.
          </li>
          <li className="muted" style={{ marginBottom: 6 }}>
            <strong>Reveal window</strong> — bidders reveal the real amount +
            salt. Masked overage refunds atomically. Bid sizes appear on-chain
            only here.
          </li>
          <li className="muted" style={{ marginBottom: 6 }}>
            <strong>Settle</strong> — anyone calls it. Clears at one uniform
            price <span className="mono">P = total / offered</span>, seeds
            full-range LP, opens trading.
          </li>
          <li className="muted">
            <strong>Claim / reclaim</strong> — bidders claim their pro-rata
            allocation. Non-revealers reclaim their masked deposit. First-block
            and last-block buyers get the identical price.
          </li>
        </ol>
      </div>

      <div className="card" style={{ marginTop: 20 }}>
        <h2>Pick a launch</h2>
        <div className="field">
          <label>CommitRevealLaunch manager address</label>
          <input
            className="input mono"
            value={launchInput}
            onChange={(e) => setLaunchInput(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Pool id (bytes32)</label>
          <input
            className="input mono"
            value={poolIdInput}
            onChange={(e) => setPoolIdInput(e.target.value)}
          />
        </div>
        <div className="actions">
          <button className="btn" onClick={onLoad}>
            Load
          </button>
          <button
            className="btn ghost"
            onClick={() => {
              setLaunchInput(DEMO_LAUNCH);
              setPoolIdInput(DEMO_POOL_ID);
              setLaunchAddr(DEMO_LAUNCH);
              setPoolId(DEMO_POOL_ID);
            }}
          >
            Reset to demo
          </button>
        </div>
      </div>

      {isLoading && (
        <p className="notice" style={{ marginTop: 20 }}>
          Loading auction state…
        </p>
      )}
      {error && (
        <p className="notice err" style={{ marginTop: 20 }}>
          Couldn&apos;t read this launch — check the address + poolId.{" "}
          <span className="muted">{(error as Error).message}</span>
        </p>
      )}

      {data && phase && (
        <div className="grid">
          <LaunchSummary
            launch={data.launch}
            phase={phase}
            now={now}
            launchAddr={launchAddr}
            poolId={poolId}
          />
          <YourBid bid={data.bid} account={address} />
          <ActionPanel
            launch={data.launch}
            bid={data.bid}
            phase={phase}
            now={now}
            launchAddr={launchAddr}
            poolId={poolId}
            refetch={() => {
              void refetch();
            }}
          />
        </div>
      )}
    </main>
  );
}
