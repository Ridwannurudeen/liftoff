import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import { Providers } from "./providers";
import "./globals.css";

const SITE_URL = "https://liftoff.gudman.xyz";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Sealed Launch — auction lifecycle",
    template: "%s · Sealed Launch",
  },
  description:
    "Drive a Sealed Launch (Uniswap v4 hook on X Layer) auction end-to-end: commit a sealed bid, reveal, settle, claim.",
  applicationName: "Sealed Launch",
  keywords: [
    "Uniswap v4",
    "X Layer",
    "sealed batch auction",
    "fair launch",
    "OKX",
    "token launch",
    "commit reveal",
  ],
  openGraph: {
    type: "website",
    url: `${SITE_URL}/app`,
    siteName: "Sealed Launch",
    title: "Sealed Launch — order-independent batch auctions on X Layer",
    description:
      "A sealed, uniform-price batch auction inside a Uniswap v4 hook. Everyone clears at one price. Order doesn't matter.",
    images: [
      {
        url: "/og-image.svg",
        width: 1200,
        height: 630,
        alt: "Sealed Launch — order doesn't matter, one uniform price",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Sealed Launch — order-independent batch auctions on X Layer",
    description:
      "Sealed, uniform-price batch auctions for token launches — a Uniswap v4 hook on X Layer.",
    images: ["/og-image.svg"],
  },
  manifest: "/app/manifest.webmanifest",
  alternates: { canonical: `${SITE_URL}/app` },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: "#06070d",
  colorScheme: "dark",
  width: "device-width",
  initialScale: 1,
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
