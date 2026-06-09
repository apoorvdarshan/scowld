import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  turbopack: {
    root: process.cwd(),
  },
  // Consolidate ranking signals on the apex domain: 301 redirect www -> non-www.
  async redirects() {
    return [
      {
        source: "/:path*",
        has: [{ type: "host", value: "www.scowld.xyz" }],
        destination: "https://scowld.xyz/:path*",
        permanent: true,
      },
    ];
  },
};

export default nextConfig;
