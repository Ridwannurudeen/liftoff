"use client";

import { useMemo, useState } from "react";
import {
  COMMIT_REVEAL_LAUNCH_V2,
  SEALED_LAUNCH_V1,
  createLaunch,
  type LaunchParams,
} from "sealed-launch-sdk";
import { erc20Abi, isAddress, parseUnits, type Address, type Hex } from "viem";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useWalletClient,
} from "wagmi";

import { ConnectButton } from "@/components/ConnectButton";
import { xLayer } from "@/lib/chain";
import { walletErrorMessage } from "@/lib/walletNetwork";

const DEFAULT_QUOTE: Address = "0x632bdC371EF86b9238dE795aEE2babABE3A5A277";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

// Mirror the `/app` allowlist. The form defaults to the curated v2 manager;
// any override gets a loud warning so a phishing pre-fill can't quietly
// redirect `createLaunch` at a hostile manager.
const KNOWN_LAUNCHES: ReadonlySet<string> = new Set(
  [COMMIT_REVEAL_LAUNCH_V2, SEALED_LAUNCH_V1].map((a) => a.toLowerCase()),
);

// Strict positive-integer regex — rejects "+1800", "01800", "1800.0", " 1800".
const POSITIVE_INT_RE = /^[1-9][0-9]*$/;

type Status =
  | { kind: "idle" }
  | { kind: "pending"; msg: string }
  | { kind: "error"; msg: string }
  | {
      kind: "ok";
      msg: string;
      tx: Hex;
      poolId: Hex;
      token: Address;
      launch: Address;
    };

export default function CreateLaunchPage() {
  const { address } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient({ chainId: 196 });
  const { data: walletClient } = useWalletClient();

  const [name, setName] = useState("Demo Launch Token");
  const [symbol, setSymbol] = useState("DEMO");
  const [totalSupplyStr, setTotalSupplyStr] = useState("1000000");
  const [offeredStr, setOfferedStr] = useState("400000");
  const [lpStr, setLpStr] = useState("300000");
  const [quoteStr, setQuoteStr] = useState<string>(DEFAULT_QUOTE);
  const [commitWindowStr, setCommitWindowStr] = useState("1800");
  const [revealWindowStr, setRevealWindowStr] = useState("1800");
  const [minRaiseStr, setMinRaiseStr] = useState("0");
  const [maxMaskedStr, setMaxMaskedStr] = useState("0");
  const [tickSpacingStr, setTickSpacingStr] = useState("60");
  const [launchInput, setLaunchInput] = useState<string>(
    COMMIT_REVEAL_LAUNCH_V2,
  );

  const [status, setStatus] = useState<Status>({ kind: "idle" });

  const onWrongChain = Boolean(address) && chainId !== xLayer.id;

  // Live preview of launcher-residual tokens. If totalSupply equals
  // offered + lp, the launcher receives zero — surface that explicitly so
  // the user notices before paying gas.
  const launcherResidual = useMemo(() => {
    try {
      const total = parseUnits(totalSupplyStr || "0", 18);
      const offered = parseUnits(offeredStr || "0", 18);
      const lp = parseUnits(lpStr || "0", 18);
      if (total < offered + lp) return null;
      return total - offered - lp;
    } catch {
      return null;
    }
  }, [totalSupplyStr, offeredStr, lpStr]);

  // Detect overrides off the curated allowlist so the UI can warn loudly.
  const trimmedLaunch = launchInput.trim();
  const launchKnown =
    isAddress(trimmedLaunch) && KNOWN_LAUNCHES.has(trimmedLaunch.toLowerCase());

  const canSubmit = useMemo(
    () =>
      Boolean(address) &&
      !onWrongChain &&
      Boolean(walletClient) &&
      Boolean(publicClient) &&
      status.kind !== "pending",
    [address, onWrongChain, walletClient, publicClient, status.kind],
  );

  const onSubmit = async () => {
    try {
      if (!walletClient) throw new Error("connect a wallet first");
      if (!publicClient) throw new Error("no public client for chain 196");
      if (!address) throw new Error("no account");

      const launchAddrStr = launchInput.trim();
      if (!isAddress(launchAddrStr)) {
        throw new Error("invalid CommitRevealLaunch manager address");
      }
      const launchAddr = launchAddrStr as Address;

      const quoteStrTrim = quoteStr.trim();
      if (!isAddress(quoteStrTrim)) {
        throw new Error("invalid quote token address");
      }
      if (quoteStrTrim.toLowerCase() === ZERO_ADDRESS.toLowerCase()) {
        throw new Error("quote token cannot be the zero address");
      }
      const quote = quoteStrTrim as Address;

      // Confirm the quote address is actually an ERC-20 before charging the
      // user gas to deploy a token + open a pool that will never settle.
      setStatus({ kind: "pending", msg: "Checking quote token…" });
      try {
        await publicClient.readContract({
          address: quote,
          abi: erc20Abi,
          functionName: "symbol",
        });
        await publicClient.readContract({
          address: quote,
          abi: erc20Abi,
          functionName: "decimals",
        });
      } catch {
        throw new Error(
          "Quote address doesn't look like an ERC-20 — check the address or use the demo dUSD2.",
        );
      }

      const totalSupply = parseUnits(totalSupplyStr || "0", 18);
      const offeredTokens = parseUnits(offeredStr || "0", 18);
      const lpTokens = parseUnits(lpStr || "0", 18);
      const minRaise = parseUnits(minRaiseStr || "0", 18);
      const maxMaskedPerWallet = parseUnits(maxMaskedStr || "0", 18);

      if (totalSupply <= 0n) throw new Error("total supply must be > 0");
      if (offeredTokens <= 0n) throw new Error("offered tokens must be > 0");
      if (lpTokens <= 0n) throw new Error("lp tokens must be > 0");
      if (totalSupply < offeredTokens + lpTokens) {
        throw new Error("total supply must be >= offered + lp");
      }

      if (!POSITIVE_INT_RE.test(commitWindowStr.trim())) {
        throw new Error(
          "commit window must be a positive integer (no leading zeros, no +/whitespace)",
        );
      }
      if (!POSITIVE_INT_RE.test(revealWindowStr.trim())) {
        throw new Error(
          "reveal window must be a positive integer (no leading zeros, no +/whitespace)",
        );
      }
      const commitWindow = BigInt(commitWindowStr.trim());
      const revealWindow = BigInt(revealWindowStr.trim());

      const tickSpacing = Number(tickSpacingStr);
      if (!Number.isInteger(tickSpacing) || tickSpacing <= 0) {
        throw new Error("tick spacing must be a positive integer");
      }

      const startTime = BigInt(Math.floor(Date.now() / 1000));
      const commitEnd = startTime + commitWindow;
      const revealEnd = commitEnd + revealWindow;

      const params: LaunchParams = {
        name,
        symbol,
        totalSupply,
        offeredTokens,
        lpTokens,
        quote,
        startTime,
        commitEnd,
        revealEnd,
        minRaise,
        maxMaskedPerWallet,
        tickSpacing,
      };

      setStatus({ kind: "pending", msg: "Deploying launch…" });
      const result = await createLaunch(
        {
          wallet: walletClient,
          public: publicClient,
          launch: launchAddr,
          account: address,
        },
        params,
      );

      setStatus({
        kind: "ok",
        msg: "Launch open.",
        tx: result.txHash,
        poolId: result.poolId,
        token: result.token,
        launch: launchAddr,
      });
    } catch (e: unknown) {
      setStatus({ kind: "error", msg: walletErrorMessage(e) });
    }
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
        <h1>Open your own sealed auction</h1>
        <p>
          Deploy a fresh ERC-20 and open a CommitRevealLaunch pool in one tx.
          Bidders post hashed commitments during the commit window, reveal the
          real amounts, then anyone calls settle — the pool clears at one
          uniform price <span className="mono">P = total / offered</span> and
          gets seeded with full-range LP that opens trading.
        </p>
      </section>

      <div className="card" style={{ marginTop: 28 }}>
        <h2>Launch parameters</h2>

        <div className="field">
          <label>Token name</label>
          <input
            className="input"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Token symbol</label>
          <input
            className="input"
            value={symbol}
            onChange={(e) => setSymbol(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Total supply (18 decimals)</label>
          <input
            className="input"
            inputMode="decimal"
            value={totalSupplyStr}
            onChange={(e) => setTotalSupplyStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Offered tokens (sold to bidders)</label>
          <input
            className="input"
            inputMode="decimal"
            value={offeredStr}
            onChange={(e) => setOfferedStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>LP tokens (seeded into the pool)</label>
          <input
            className="input"
            inputMode="decimal"
            value={lpStr}
            onChange={(e) => setLpStr(e.target.value)}
          />
          {launcherResidual !== null && launcherResidual === 0n && (
            <p className="notice warn" style={{ marginTop: 6 }}>
              Launcher receives 0 tokens after settlement (totalSupply ==
              offered + lp). Is this intentional?
            </p>
          )}
        </div>
        <div className="field">
          <label>
            Quote token address{" "}
            <span className="muted">
              — default is the demo MockERC20 dUSD2 (public mint; faucet on
              /app)
            </span>
          </label>
          <input
            className="input mono"
            value={quoteStr}
            onChange={(e) => setQuoteStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Commit window (seconds)</label>
          <input
            className="input"
            inputMode="decimal"
            value={commitWindowStr}
            onChange={(e) => setCommitWindowStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Reveal window (seconds)</label>
          <input
            className="input"
            inputMode="decimal"
            value={revealWindowStr}
            onChange={(e) => setRevealWindowStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Min raise (quote, 18 decimals) — 0 disables</label>
          <input
            className="input"
            inputMode="decimal"
            value={minRaiseStr}
            onChange={(e) => setMinRaiseStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>
            Max masked deposit per wallet (18 decimals) — 0 disables
          </label>
          <input
            className="input"
            inputMode="decimal"
            value={maxMaskedStr}
            onChange={(e) => setMaxMaskedStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>Tick spacing</label>
          <input
            className="input"
            inputMode="decimal"
            value={tickSpacingStr}
            onChange={(e) => setTickSpacingStr(e.target.value)}
          />
        </div>
        <div className="field">
          <label>
            CommitRevealLaunch manager address{" "}
            <span className="muted">— advanced; leave as default</span>
          </label>
          <input
            className="input mono"
            value={launchInput}
            onChange={(e) => setLaunchInput(e.target.value)}
          />
          {!launchKnown && (
            <p className="notice err" style={{ marginTop: 6 }}>
              ⚠ This launch manager is not curated by Sealed Launch. Deploying
              against an unverified manager can hand the deployer&apos;s funds
              and the new token to a hostile contract. Reset to the default
              unless you trust the address.
            </p>
          )}
        </div>

        <div className="actions">
          <button className="btn" disabled={!canSubmit} onClick={onSubmit}>
            {status.kind === "pending" ? "Deploying…" : "Deploy launch"}
          </button>
          <a className="btn ghost" href="/app">
            Back to lifecycle viewer
          </a>
        </div>

        {!address && (
          <p className="notice">Connect a wallet to deploy a launch.</p>
        )}
        {onWrongChain && (
          <p className="notice warn">
            Switch your wallet to X Layer Mainnet (chain 196) before deploying.
          </p>
        )}

        {status.kind === "pending" && (
          <p className="notice warn">{status.msg}</p>
        )}
        {status.kind === "error" && <p className="notice err">{status.msg}</p>}
        {status.kind === "ok" && (
          <div className="notice ok" style={{ display: "grid", gap: 8 }}>
            <div>✅ Launch open.</div>
            <div className="row">
              <span className="k">Tx</span>
              <a
                className="v mono"
                href={`https://www.oklink.com/xlayer/tx/${status.tx}`}
                target="_blank"
                rel="noreferrer"
              >
                {status.tx}
              </a>
            </div>
            <div className="row">
              <span className="k">Launch manager</span>
              <a
                className="v mono"
                href={`https://www.oklink.com/xlayer/address/${status.launch}`}
                target="_blank"
                rel="noreferrer"
              >
                {status.launch}
              </a>
            </div>
            <div className="row">
              <span className="k">New token</span>
              <a
                className="v mono"
                href={`https://www.oklink.com/xlayer/address/${status.token}`}
                target="_blank"
                rel="noreferrer"
              >
                {status.token}
              </a>
            </div>
            <div className="row">
              <span className="k">Pool id</span>
              <span className="v mono">{status.poolId}</span>
            </div>
            <div className="actions">
              <a
                className="btn"
                href={`/app?launch=${status.launch}&poolId=${status.poolId}`}
              >
                Drive this auction →
              </a>
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
