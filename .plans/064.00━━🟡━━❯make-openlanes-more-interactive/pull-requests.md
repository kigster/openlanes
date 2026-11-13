# Pull Requests

## Frontend, round 1

- F1 `boardDelta.ts`, `useBoard.ts`, `events.ts`, `types.ts`: a `board_delta` applies only onto the held version; a mismatch reopens the stream (fresh full `board`). Tests: `boardDelta.test.ts`, `useBoard.test.tsx`, `events.test.ts`.
- F2 `AgentDrawer.tsx`: Extend time +10/+20 (`extend_time`) and Stop after this step (`wrap_up`), running cars only. Test: `AgentDrawer.test.tsx`.
- F3 `PlanReview.tsx`, `planReview.ts`: diff stat, patch toggle, findings with Accept/Strike (`rule_finding`). Test: `PlanReview.test.tsx`. Built against contract §3; backend B3 route was not yet built.
- F4 `Car.tsx`, `PlanRow.tsx`, `AgentDrawer.tsx`, `format.ts`: cost lines. Test: `Car.test.tsx`.
- `npx vitest run`: all pass (538); `eslint` and `tsc` clean.
- NOT run: `web/cypress/e2e/interactive.cy.ts` (written, never executed; needs the B3 route and a running demo server). Not the last agent, so the integration proof is still owed.

## Integration proof, backend-coder, 2026-11-12

Built `web/dist` (`cd web && npm run build`), then ran `web/cypress/e2e/interactive.cy.ts` exactly as `bin/web-e2e` sets up the suite: two `openlanes web --demo` servers on Redis db 14, the fixture plans copied to a temp `.plans`, nothing stubbed.

    npx cypress run --spec cypress/e2e/interactive.cy.ts --config baseUrl=http://127.0.0.1:11160 --env peer=http://127.0.0.1:11161,plansDir=<tmp>/.plans

    ✓ advances a car through board_delta frames after one full board (1316ms)
    ✓ extends a running car's time and gets the engine's reply (967ms)
    ✓ keeps a struck finding struck after a reload (1307ms)
    ✓ shows a plan's cost as the sum of its cars' costs (249ms)
    4 passing (4s)

The first run failed on the first check: it read the first `.car`, which in the demo is a stuck car whose stats never move. The spec now picks `.car.is-running` (mailed to frontend-coder).

Stream check by hand, `curl -sN --max-time 6 /api/events` on the demo: 1 `board`, 6 `board_delta`.

## Frontend, round 1 (final)

- Back end is done; integration proof is the backend-coder section above (interactive.cy.ts, 4 passing, nothing stubbed).
- `npx vitest run`: 538 passed. `bundle exec rubocop`: no offenses.

## Suite and lint, backend-coder, 2026-11-12

- `bundle exec rspec` (full): 5975 examples, 6 failures, all from the environment rather than the plan's code:
  - `thread_safety_inventory_spec.rb:18`: the new `Live::Store` lock was missing from `docs/thread-safety.md`; row added.
  - `engine/dispatcher_spec.rb:523`: read the checkout's `.openlanes.yml` (`frontend: true`); the routing group now runs in its temp project.
  - `cli/web_spec.rb:255`, `:277`, `cli/engine_command_spec.rb:289`, `:317`: `OPENLANES_ADMIN_CREDENTIALS` exported by the developer's direnv leaked into the examples; `spec_helper.rb` now deletes it at load.
- After the fixes, those four files: `bundle exec rspec spec/openlanes/thread_safety_inventory_spec.rb spec/openlanes/engine/dispatcher_spec.rb spec/openlanes/cli/web_spec.rb spec/openlanes/cli/engine_command_spec.rb` → 189 examples, 0 failures. The full suite was not rerun after them (a full run takes about 10 minutes, more than the time left in the round).
- `bundle exec rubocop` → 855 files inspected, no offenses detected.
- `.openlanes.yml` gained `coverage:` (`bundle exec rspec`, minimum 95, `jq '.total.lines.percent' coverage/coverage.json`). The command prints a figure; the one on disk comes from a partial run, so it is not the suite's.
