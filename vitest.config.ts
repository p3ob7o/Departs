import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    environment: "jsdom",
    environmentMatchGlobs: [["app/api/**/*.test.ts", "node"]],
    exclude: ["e2e/**", "node_modules/**"],
    setupFiles: ["app/__tests__/setup.ts"],
    coverage: {
      provider: "v8",
      include: ["app/components/**", "app/hooks/**", "app/lib/**", "app/api/**"],
      thresholds: {
        statements: 80,
        branches: 80,
        functions: 80,
        lines: 80,
      },
    },
  },
});
