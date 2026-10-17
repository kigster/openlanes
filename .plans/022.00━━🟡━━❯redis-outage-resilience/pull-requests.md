# Pull Requests

## F1 front end (rey-frontend, round 1)

- `cd web && npx vitest run`: 34 files, 358 tests passed.
- `cd web && npx eslint .` and `npx tsc -b`: no findings.
- Tests for F1: `web/src/shell/Header.test.tsx`, "Redis outage notice" (fresh and null: silent; stale: alert; recovered: status line).
