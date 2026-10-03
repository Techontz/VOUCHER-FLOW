import type { MetadataRoute } from "next";

/** Lets a phone add VouchFlow to its home screen with the brand mark as its icon. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "VouchFlow",
    short_name: "VouchFlow",
    description: "Voucher approvals, signed and on the record.",
    start_url: "/dashboard",
    display: "standalone",
    background_color: "#ffffff",
    theme_color: "#0B3D91",
    icons: [
      { src: "/brand/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/brand/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
  };
}
