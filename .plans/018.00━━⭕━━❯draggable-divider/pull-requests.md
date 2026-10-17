# Pull Requests

## Front end proof (rey-frontend, round 1)

- `cd web && npx vitest run --coverage`: 35 files, 361 tests passed; lines 99.74%.
- `cd web && npm run lint`: clean. `npm run typecheck`: clean.
- `just web-build`: built.
- `E2E_PORT=11840 E2E_PEER_PORT=11841 E2E_REDIS_URL=redis://localhost:6379/9 just web-e2e`: 6 specs, 30 tests, all passed, including `divider.cy.ts` (7/7).
  (A first run on the default ports lost its server mid-run, a port/Redis collision with another session; not a code failure.)

Acceptance criteria to tests: placement, drag without jump, clamps, reload persistence, car open/close, keys 24px/Home/dblclick, scrolled-drawer visibility, absent at 900px: `divider.cy.ts`. Hook: `useSideWidth.test.ts`. Component: `ColumnDivider.test.tsx`. Wiring: `App.test.tsx`.

## Back end and integration proof (luke-backend, round 1, last to finish)

Run in `openlanes.worktrees/018.00-draggable-divider` after rey's front end landed.

- `bundle exec rspec spec/openlanes/web`: 167 examples, 0 failures.
- `bundle exec rspec`: 3013 examples, 0 failures.
- `bundle exec rubocop`: 425 files inspected, no offenses detected.
- `just web-build && just web-e2e`: built; 6 specs all passed (`actions` 5, `board` 6, `chat` 4, `divider` 7, `keyboard` 5, `needs-you`), exit 0.
- `docs/badges/coverage_badge.svg`: reverted after each rspec run.


## Rerun after harness restart (luke-backend, round 1, 2026-10-15 evening)

- `bundle exec rspec`: 3013 examples, 0 failures.
- `bundle exec rubocop`: 425 files inspected, no offenses detected.
- `just web-build`: built; `web/dist/assets/index-Cr6Ijz7s.js` contains `Resize side panel`.
- `E2E_PORT=11850 E2E_PEER_PORT=11851 E2E_REDIS_URL=redis://localhost:6379/9 just web-e2e`: 6 specs, 30 tests, all passed (`divider.cy.ts` 7/7), exit 0.
- `docs/badges/coverage_badge.svg`: unchanged; nothing outside `web/` in `git status`.

## Rerun after harness restart (luke-backend, round 1, 2026-10-16)

- `bundle exec rspec`: 3013 examples, 0 failures.
- `bundle exec rubocop`: 425 files inspected, no offenses detected.
- `bundle exec rspec spec/openlanes/web`: 167 examples, 0 failures.
- `just web-build`: built; `web/dist/assets/index-Cr6Ijz7s.js` contains `Resize side panel`.
- `E2E_PORT=11860 E2E_PEER_PORT=11861 E2E_REDIS_URL=redis://localhost:6379/9 just web-e2e`: 6 specs, 30 tests, all passed (`divider.cy.ts` 7/7), exit 0.
- `docs/badges/coverage_badge.svg`: rewritten by rspec, reverted with `git checkout`; nothing outside `web/` in `git status`.

## Rerun after harness restart (luke-backend, round 1, 2026-10-16 evening)

- `bundle exec rubocop`: 425 files inspected, no offenses detected.
- `bundle exec rspec spec/openlanes/web`: 167 examples, 0 failures.
- `just web-build`: built; `web/dist/assets/index-Cr6Ijz7s.js` contains `Resize side panel`.
- `E2E_PORT=11870 E2E_PEER_PORT=11871 E2E_REDIS_URL=redis://localhost:6379/9 just web-e2e`: all specs passed (`divider.cy.ts` 7/7), exit 0.
- `bundle exec rspec`, four runs under load average 6 to 14 with rey running beside: 3013 examples, 1 to 4 failures, a different process/port spec each run (`spec/integration/restart_spec.rb:63`, `spec/openlanes/apps/supervisor_spec.rb:74,86,133`, `spec/openlanes/apps/restart_spec.rb:77`, `spec/integration/two_checkouts_spec.rb:70`). `spec/integration/restart_spec.rb` alone: 2/0, twice. This branch changes no Ruby (`git status` shows only `web/`), and the same suite was 3013/0 at 10:11 today.

## Rerun after harness restart (rey-frontend, round 1, 2026-10-16)

- `cd web && npx vitest run`: 35 files, 361 tests passed. `npm run lint` and `npm run typecheck`: clean.
- `bundle exec rubocop`: 425 files inspected, no offenses detected.
- `bundle exec rspec`: ran to completion (coverage 98.71%); the examples line was cut off by `tail`, so the count rests on luke's 3013/0 from the same tree.
- Nothing outside `web/` in `git status`.
