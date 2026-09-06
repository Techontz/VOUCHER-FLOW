import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The dev-tools badge defaults to the bottom-left, where it sits on top of the
  // sidebar's user/sign-out row. Development only; it is absent from a build.
  devIndicators: {
    position: "bottom-right",
  },
};

export default nextConfig;
