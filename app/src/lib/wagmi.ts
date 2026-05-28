import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";

import { xLayer } from "./chain";

export const wagmiConfig = createConfig({
  chains: [xLayer],
  connectors: [injected({ shimDisconnect: true })],
  transports: {
    [xLayer.id]: http(),
  },
  ssr: true,
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
