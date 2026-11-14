# Pull Requests

## Frontend, round 1 (frontend-coder)

- `cd web && npx vitest run`: 52 files, 554 tests passed. `npx tsc --noEmit` and `npx eslint src cypress`: clean.
- `bin/web-e2e` (after `npm run build` in `web/`): 10 specs, 48 tests, all passed, including `round-ledger.cy.ts`.
- Backend integration proof (`restart_rounds_spec.rb`) is backend-coder's B6 and has not run: B2 to B6 were still open when this round ended.
- Deviation: the rounds request's three choices are asserted in vitest (`NeedsYou.test.tsx`, `AgentDrawer.test.tsx`), not in Cypress. The demo board (`web/src/api/fixtures/board.json`) is shared with the unit tests, and any plan that carries a request changes question counts in nine of them.

## Backend, round 5 (backend-coder)

- Integration proof: `bundle exec rspec spec/openlanes/engine/restart_rounds_spec.rb`, 6 examples, 0 failures. A real `Runner` and `Executor` drive a fake `claude` that signs the round it was told: restart continues at 2 and 3, an auth failure spends no round and holds `claude`, and the same round is handed out once the probe passes.
- `bundle exec rubocop`: 912 files inspected, no offenses detected.
- First full `bundle exec rspec`: 6260 examples, 7 failures. Three were caused by this plan and are fixed (`thread_safety_inventory_spec.rb:18`, `cli/run_spec.rb:557`, `integration/resume_across_rounds_spec.rb:155`; the last two now expect a zero-token failure to be a failed start). The other four are the baseline (`cli/engine_command_spec.rb:289,317`, `cli/web_spec.rb:255,277`): they fail only because this machine exports `OPENLANES_ADMIN_CREDENTIALS`.

## Frontend, round 1 rerun (frontend-coder)

Rerun after backend-coder landed `paused_clis` in the snapshot (mail 5):

- `cd web && npx vitest run`: Test Files 52 passed (52), Tests 554 passed (554).
- `npx tsc --noEmit` and `npx eslint src cypress`: no output, clean.
- `npm run build` then `bin/web-e2e`: All specs passed, 10 specs, 48 tests, 48 passing, including `round-ledger.cy.ts` (2/2).
- The back-end integration proof (`restart_rounds_spec.rb`) is backend-coder's and was not run by me.
- Final full run, after the last edit: `env -u OPENLANES_ADMIN_CREDENTIALS bundle exec rspec`: 6260 examples, 0 failures, coverage 99.23%, exit 0.
- Front end: frontend-coder's round 1 results above (vitest 554 passed, `bin/web-e2e` 48 passed). The only front-end file I touched since was `web/src/api/fixtures/snapshot.json` (`"paused_clis": []`), mailed as #5.
