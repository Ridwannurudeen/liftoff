import type { AddEthereumChainParameter, EIP1193Provider } from "viem";

import { X_LAYER_CHAIN_ID_HEX, X_LAYER_RPC_URL, xLayer } from "@/lib/chain";

const xLayerWalletParams = {
  chainId: X_LAYER_CHAIN_ID_HEX,
  chainName: xLayer.name,
  nativeCurrency: xLayer.nativeCurrency,
  rpcUrls: [X_LAYER_RPC_URL],
  blockExplorerUrls: [xLayer.blockExplorers.default.url],
} satisfies AddEthereumChainParameter;

const RABBY_RPC_FIX =
  "Rabby has a stale X Layer network saved. Edit or remove X Layer Mainnet in Rabby, then add it with chain ID 196 (0xc4), RPC https://rpc.xlayer.tech, symbol OKB. Do not use the testnet RPC https://testrpc.xlayer.tech/terigon for this app.";

export async function ensureXLayerNetwork() {
  const provider = getInjectedProvider();
  if (!provider) throw new Error("No injected wallet found.");

  try {
    await switchToXLayer(provider);
  } catch (switchError) {
    if (isUserRejected(switchError)) throw switchError;

    try {
      await provider.request({
        method: "wallet_addEthereumChain",
        params: [xLayerWalletParams],
      });
      await switchToXLayer(provider);
    } catch (addError) {
      if (isRpcChainMismatch(switchError) || isRpcChainMismatch(addError)) {
        throw new Error(RABBY_RPC_FIX);
      }
      throw addError;
    }
  }

  const chainId = await provider.request({ method: "eth_chainId" });
  if (chainId.toLowerCase() !== X_LAYER_CHAIN_ID_HEX) {
    throw new Error(
      `Wallet switched to ${chainId}, expected ${X_LAYER_CHAIN_ID_HEX}.`,
    );
  }
}

export function walletErrorMessage(error: unknown): string {
  if (isRpcChainMismatch(error)) return RABBY_RPC_FIX;
  return errorMessage(error) || "unknown error";
}

function getInjectedProvider(): EIP1193Provider | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as Window & { ethereum?: EIP1193Provider }).ethereum;
}

function switchToXLayer(provider: EIP1193Provider) {
  return provider.request({
    method: "wallet_switchEthereumChain",
    params: [{ chainId: X_LAYER_CHAIN_ID_HEX }],
  });
}

function isUserRejected(error: unknown): boolean {
  return errorCode(error) === 4001;
}

function isRpcChainMismatch(error: unknown): boolean {
  const message = errorMessage(error).toLowerCase();
  return (
    message.includes("invalid chain id") ||
    message.includes("rpc invalid") ||
    message.includes("currently unavailable")
  );
}

function errorCode(error: unknown): number | undefined {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return undefined;
  }
  const code = (error as { code: unknown }).code;
  return typeof code === "number" ? code : undefined;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message: unknown }).message;
    if (typeof message === "string") return message;
  }
  return "";
}
