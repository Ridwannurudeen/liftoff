"use client";

import { useState } from "react";
import type { EIP1193Provider } from "viem";
import {
  useAccount,
  useChainId,
  useConnect,
  useConnections,
  useDisconnect,
} from "wagmi";

import { xLayer } from "@/lib/chain";
import { ensureXLayerNetwork, walletErrorMessage } from "@/lib/walletNetwork";

function truncate(addr: string) {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending: connecting } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const connections = useConnections();
  const [switching, setSwitching] = useState(false);
  const [switchError, setSwitchError] = useState<string | null>(null);

  const injected =
    connectors.find((c) => c.type === "injected") ?? connectors[0];
  const wrongChain = isConnected && chainId !== xLayer.id;

  if (!isConnected) {
    return (
      <button
        className="btn"
        disabled={!injected || connecting}
        onClick={() => injected && connect({ connector: injected })}
      >
        {connecting ? "Connecting..." : "Connect wallet"}
      </button>
    );
  }

  if (wrongChain) {
    return (
      <div style={{ display: "grid", gap: 8, justifyItems: "end" }}>
        <button
          className="btn"
          disabled={switching}
          onClick={async () => {
            setSwitching(true);
            setSwitchError(null);
            let provider: EIP1193Provider | undefined;
            try {
              const connector = connections[0]?.connector;
              provider = (await connector?.getProvider?.()) as
                | EIP1193Provider
                | undefined;
              await ensureXLayerNetwork(provider);
            } catch (e: unknown) {
              setSwitchError(
                walletErrorMessage(e, { chainSwitch: true, provider }),
              );
            } finally {
              setSwitching(false);
            }
          }}
        >
          {switching ? "Switching..." : "Switch to X Layer"}
        </button>
        {switchError && (
          <p
            className="notice err"
            style={{ maxWidth: 420, marginTop: 0, textAlign: "right" }}
          >
            {switchError}
          </p>
        )}
      </div>
    );
  }

  return (
    <button className="btn ghost" onClick={() => disconnect()}>
      {address ? truncate(address) : "Connected"} - disconnect
    </button>
  );
}
