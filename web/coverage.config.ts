// What coverage measures, read by vite.config.ts and by scripts/coverage-changed.ts alike. With the gate holding its
// own copy, a file vitest was told to leave out (src/main.tsx, src/api/types.ts) never appeared in the report, and the
// first branch that touched one would have been failed at 0%.
export const COVERAGE_INCLUDE = ["src/**/*.{ts,tsx}"];
export const COVERAGE_EXCLUDE = ["src/**/*.test.{ts,tsx}", "src/test/**", "src/main.tsx", "src/vite-env.d.ts", "src/api/types.ts"];
