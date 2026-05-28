import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";

import { X_LAYER_RPC_URL, xLayer } from "./chain";

export const wagmiConfig = createConfig({
  chains: [xLayer],
  connectors: [injected({ shimDisconnect: true })],
  transports: {
    [xLayer.id]: http(X_LAYER_RPC_URL),
  },
  ssr: true,
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
