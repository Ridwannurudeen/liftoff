import {
  BaseError,
  type AddEthereumChainParameter,
  type EIP1193Provider,
} from "viem";

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

const GENERIC_CHAIN_MISMATCH_FIX =
  "Your wallet's saved X Layer RPC is rejecting the chain ID. Open your wallet's network list, remove X Layer Mainnet, then re-add it with chain ID 196 (0xc4) and RPC https://rpc.xlayer.tech.";

/**
 * Route chain-switch / chain-add calls through the *connected* wallet provider
 * rather than `window.ethereum`. In an EIP-6963 multi-wallet browser the
 * global injected provider is whichever extension won the race — not
 * necessarily the wallet wagmi connected to. Callers pass the provider they
 * fetched off the wagmi connector via `connector.getProvider()`.
 */
export async function ensureXLayerNetwork(
  provider: EIP1193Provider | undefined,
) {
  if (!provider) throw new Error("No connected wallet provider.");

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
        throw new Error(chainMismatchFixFor(provider));
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

/**
 * Sanitize an error for the UI. Caller-provided `context` lets us only show
 * the chain-mismatch runbook when the user was actually in the
 * chain-switch flow — otherwise a transient RPC throttle ("currently
 * unavailable") gets misdiagnosed as a wallet-config problem.
 */
export function walletErrorMessage(
  error: unknown,
  context?: { chainSwitch?: boolean; provider?: EIP1193Provider },
): string {
  if (context?.chainSwitch && isRpcChainMismatch(error)) {
    return chainMismatchFixFor(context.provider);
  }
  if (error instanceof BaseError) return error.shortMessage;
  return errorMessage(error) || "unknown error";
}

function chainMismatchFixFor(provider: EIP1193Provider | undefined): string {
  return isRabby(provider) ? RABBY_RPC_FIX : GENERIC_CHAIN_MISMATCH_FIX;
}

function isRabby(provider: EIP1193Provider | undefined): boolean {
  if (!provider) return false;
  const p = provider as EIP1193Provider & { isRabby?: boolean };
  return p.isRabby === true;
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
    message.includes("invalid chain id") || message.includes("rpc invalid")
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
  if (error instanceof BaseError) return error.shortMessage;
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message: unknown }).message;
    if (typeof message === "string") return message;
  }
  return "";
}
