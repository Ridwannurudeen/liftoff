"use client";

import {
  useAccount,
  useConnect,
  useDisconnect,
  useChainId,
  useSwitchChain,
} from "wagmi";

import { xLayer } from "@/lib/chain";

function truncate(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending: connecting } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const { switchChain, isPending: switching } = useSwitchChain();

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
        {connecting ? "Connecting…" : "Connect wallet"}
      </button>
    );
  }

  if (wrongChain) {
    return (
      <button
        className="btn"
        disabled={switching}
        onClick={() => switchChain({ chainId: xLayer.id })}
      >
        {switching ? "Switching…" : "Switch to X Layer"}
      </button>
    );
  }

  return (
    <button className="btn ghost" onClick={() => disconnect()}>
      {address ? truncate(address) : "Connected"} · disconnect
    </button>
  );
}
