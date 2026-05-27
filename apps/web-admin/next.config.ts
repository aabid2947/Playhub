import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Type + lint are enforced in CI via `tsc --noEmit` and `next lint`;
  // do not let a transient lint setup issue block `next build`.
  eslint: { ignoreDuringBuilds: true },
  // The web-admin only ever talks to Supabase from the server/browser via the
  // SDK, so no rewrites/headers proxying is needed here.
};

export default nextConfig;
