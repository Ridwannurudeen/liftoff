import type { Metadata } from "next";
import type { ReactNode } from "react";

import { Providers } from "./providers";
import "./globals.css";

export const metadata: Metadata = {
  title: "Sealed Launch — auction lifecycle",
  description:
    "Drive a Sealed Launch (Uniswap v4 hook on X Layer) auction end-to-end: commit a sealed bid, reveal, settle, claim.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <div className="stars" aria-hidden="true" />
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
