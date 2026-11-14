# Pull Requests

## Frontend, round 1 (frontend-coder)

- `cd web && npx vitest run`: 52 files, 554 tests passed. `npx tsc --noEmit` and `npx eslint src cypress`: clean.
- `bin/web-e2e` (after `npm run build` in `web/`): 10 specs, 48 tests, all passed, including `round-ledger.cy.ts`.
- Backend integration proof (`restart_rounds_spec.rb`) is backend-coder's B6 and has not run: B2 to B6 were still open when this round ended.
- Deviation: the rounds request's three choices are asserted in vitest (`NeedsYou.test.tsx`, `AgentDrawer.test.tsx`), not in Cypress. The demo board (`web/src/api/fixtures/board.json`) is shared with the unit tests, and any plan that carries a request changes question counts in nine of them.
