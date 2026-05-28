/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["sealed-launch-sdk"],
  // Served under sealedlaunch.gudman.xyz/app so the existing static landing keeps
  // the root. assetPrefix mirrors basePath so static chunks resolve.
  basePath: "/app",
  assetPrefix: "/app",
};

export default nextConfig;
