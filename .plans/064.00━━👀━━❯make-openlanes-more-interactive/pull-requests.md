# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 231 | [\[064.00\](A) Make Openlanes More Interactive](https://github.com/kigster/openlanes/pull/231) | Open 🟡 |

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

## Full suite rerun, backend-coder, 2026-11-12

- `bundle exec rspec` (full) → 5975 examples, 0 failures, exit 0.
- `bundle exec rubocop` → 855 files inspected, no offenses detected, exit 0.
- `jq '.total.lines.percent' coverage/coverage.json` → 99.18 (line coverage, minimum 95)

## Findings: design-reviewer

### F201 [minor] lib/openlanes/web/demo_board.rb:295

`DemoBoard#rule_finding` hand-builds the ruling hash (`kind`, `outcome`, `findings.{bucket,headings}`) that `Live::Commands.rule!` builds for the engine, and the two already differ (the demo omits `trigger`, `reason`, `pr`, `round`). The shape is written down twice. Scenario: someone makes `Findings.ruling` read `trigger: "person"` or `by`; the engine path passes and the demo board (and the Cypress proof run on it) silently shows no ruling. Give `Plans::Findings` one `ruling_for(finding, verdict, by:)` that returns the hash, and have both call it.

### F202 [minor] lib/openlanes/live/commands.rb:99

`Commands.finding!` and `Commands.rule!` are domain operations (parse a verdict, write a ruling into `PlanState`) parked as class methods on the Live command dispatcher, which `engine/arbitration_spec.rb`, `web/plan_review_spec.rb` and `DemoBoard` now call. The bucket vocabulary (`struck`/`critical`) is split across `Findings::VERDICTS`, `Findings.ruling` and `Engine::Arbitration#ruled?`. The `Arbitration::Ruling::OUTCOMES` table, which owns the ruling kinds, does not know the new `kind: "finding"`. Scenario: a new outcome is added to `Ruling::OUTCOMES`; the person-written `finding` rulings are outside it, so nothing validates them and `Counter` and `Prompt` read them by accident of shared bucket names. Move `rule!` and `finding!` beside `Findings` (or `Arbitration`) and register the kind in the ruling vocabulary; `Commands` should only call them.

### F203 [minor] lib/openlanes/web/app.rb:84

`plan_review` derives the repository root as `File.dirname(context.plans_dir)`. `$PLANS_DIR` may point anywhere, so the root is wrong whenever the plans directory is not directly under the repository. `BranchDiff` then reads another directory's refs or none, and the row shows an empty diff with no error. The root is not passed in from where `Project.root` is already known (`Context`). Add it to `Context` and pass it.

### F204 [minor] lib/openlanes/live/commands.rb:1

The file is now 802 lines (it grew by about 70 here) and holds a dispatch table, handlers and the new static helpers. The change adds a second reason to edit it (ruling storage, see F202). Moving that out leaves it smaller.
