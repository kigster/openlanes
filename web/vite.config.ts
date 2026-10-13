/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// The API server listens on 11000 (contract.md); in development Vite proxies to it, so the page has one origin either way.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 5173, proxy: { "/api": { target: "http://127.0.0.1:11000", changeOrigin: false } } },
  build: { outDir: "dist", sourcemap: true },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    css: false,
    include: ["src/**/*.test.{ts,tsx}"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.{ts,tsx}"],
      exclude: ["src/**/*.test.{ts,tsx}", "src/test/**", "src/main.tsx", "src/vite-env.d.ts", "src/api/types.ts"],
      thresholds: { statements: 95, branches: 90, functions: 95, lines: 95 },
      reporter: ["text-summary", "html", "lcov"],
    },
  },
});
