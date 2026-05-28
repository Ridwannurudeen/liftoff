import { defineChain } from "viem";

export const X_LAYER_RPC_URL = "https://rpc.xlayer.tech";
export const X_LAYER_CHAIN_ID_HEX = "0xc4";

export const xLayer = defineChain({
  id: 196,
  name: "X Layer Mainnet",
  nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
  rpcUrls: {
    default: { http: [X_LAYER_RPC_URL] },
    public: { http: [X_LAYER_RPC_URL] },
  },
  blockExplorers: {
    default: { name: "OKLink", url: "https://www.oklink.com/xlayer" },
  },
  testnet: false,
});
