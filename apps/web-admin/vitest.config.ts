import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  test: {
    environment: "node",
    setupFiles: ["./tests/setup.ts"],
    include: ["tests/**/*.test.ts"],
    // E2E (Playwright) lives under tests/e2e and is run separately.
    exclude: ["tests/e2e/**", "node_modules/**"],
    testTimeout: 20000,
    hookTimeout: 30000,
  },
});
