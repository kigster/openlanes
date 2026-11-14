# Pull Requests

## Verification, backend-coder round 1

- `bundle exec rubocop` — 993 files, no offenses.
- `npx vitest run` (web) — 69 files, 648 tests passed; `npm run lint` and `tsc --noEmit` clean.
- `bundle exec rspec` — 6645 examples, 0 failures, 9 pending (pre-existing).
- `just web-e2e` (Cypress `lane-documents.cy.ts`) — written, not run in this round (no browser run within the time budget).
