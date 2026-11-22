import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Production runs on the DirectAdmin host as a Node.js app (CloudLinux
  // Passenger), not on Vercel. "standalone" emits .next/standalone/server.js
  // with only the dependencies it needs, so the upload carries no node_modules.
  output: "standalone",
  // The dev-tools badge defaults to the bottom-left, where it sits on top of the
  // sidebar's user/sign-out row. Development only; it is absent from a build.
  devIndicators: {
    position: "bottom-right",
  },
};

export default nextConfig;
