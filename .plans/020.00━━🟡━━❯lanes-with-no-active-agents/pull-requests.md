# Pull Requests

## rey-frontend, round 1

- web: `npm test` 358 passed; `npm run lint` and `npm run typecheck` clean.
- `OPENLANES_LANES_E2E=1 just lanes-e2e` NOT run: it spends real tokens and luke had not signalled done. Files are written; the last agent or a human must run it.

## rey-frontend, round 1 (resumed)

- web: `npm test` 358 passed; `npm run lint` and `npm run typecheck` clean.
- `bundle exec rspec`: 3142 examples, 4 failures in `apps/supervisor_spec.rb` and `cli/app_spec.rb` (files untouched by this plan); both pass when run alone (22 examples, 0 failures), so they are order/port flakes in the full run.
- `OPENLANES_LANES_E2E=1 just lanes-e2e` NOT run: spends real tokens and luke-backend is not done. The last agent or a human must run it.

## luke-backend, round 1 (resumed)

- B4 built (slash parser, copilot route, 503 without a live engine, c3po paragraph); `/concurrency` now survives an engine restart. `openapi.yaml` written.
- `bundle exec rspec`: 3142 examples, 0 failures, 9 pending (one supervisor port flake on an earlier full run; passed alone and on the rerun).
- `bundle exec rubocop`: 433 files, no offenses.
- `OPENLANES_LANES_E2E=1 LANES_TIMEOUT=300 just lanes-e2e`, three runs:
  1. 1 passing, 4 failing: tests 2-5 never found `#copilot-input`. Cypress test isolation blanked the page after `before()`. Fixed: `{ testIsolation: false }` on the describe in `lanes.cy.ts` (rey mailed).
  2. 4 passing, 1 failing (step 4): `/restart B` was answered `done`. Correct: B's agent had just failed with "publish refused — plan.md has no `## How to test` section", so B had no agent. Fixed: added `## How to test` to the three fixture specs (rey mailed).
  3. 4 passing, 1 failing (step 4): `/restart A` was answered `done: 000.00 restarts at the next tick`, but no car for A appeared within 15 s. Likely cause: step 2 set concurrency to 2 and B and C still hold both slots, so A waits for a free one. Not confirmed before time ran out.
- Next step: confirm from `log/lanes-e2e/start.log` that A starts once a slot frees. If so, have step 4 wait for a free slot or raise concurrency back to 3 first. If not, look at whether `Dispatcher#restart_plan` clears everything that keeps A from dispatch after an Interrupted round ("no rounds left").
