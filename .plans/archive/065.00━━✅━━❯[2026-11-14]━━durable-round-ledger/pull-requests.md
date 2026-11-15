# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 246 | [\[065.00\](A) Durable Round Ledger](https://github.com/kigster/openlanes/pull/246) | Merged 🟣 |

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

## Findings: staff-reviewer

CI at review time: `linter` passed; `test`, `web`, `e2e` still running.

### F1 [critical] lib/openlanes/engine/dispatcher/assign.rb:313
The cap of 3 failed starts parks an agent for the rest of the visit, silently, and nothing ever lifts it. `Assign#eligible?` returns false once `Rounds#failed_starts >= 3`, and `failed_starts` counts the trailing `Failed start` stages in `state.json`. Only a stage that spent something can end that run of stages, and the agent is never started again, so the count stays at 3 until the plan moves. A restart reads the same stages and stays capped. `idle_reason` has no clause for it. A non-auth failed start is retried on the next 0.5 s tick with no backoff, so a short outage reaches the cap within seconds. The plan asked for an attention request here (plan.md, "Failed starts"). The contract dropped it, which leaves no way out short of editing `state.json` by hand.
- Input: the network drops for about 10 s. `claude` exits 1 in about 2 s with `API Error: Connection error`, with no tokens and no tool call (not an auth failure, so `CliPause` never holds the CLI).
- Expected: the agent is retried with backoff, or a person is asked, and the idle line says which agent is stuck and why.
- Actual: three `Failed start` stages land within about 8 s. The backend-coder on that plan is never assigned again on this visit, through any number of restarts. The run then reaches a fixed point with `idle: nothing to do`.
- The auth path loops the same way: `claude auth status` can report signed in while the stored OAuth token is already expired, so pause, probe pass and fail repeat until the cap is reached.
- Suggested change: exempt auth failures from the cap, or reset the count when `CliPause` releases the CLI. Back off the other failed starts. On reaching the cap, raise the attention request (`Extensions#exhausted`, or something like it) and add a clause to `idle_reason`. Add a spec that a capped agent shows up in the idle line and can be given its round again.

### F2 [minor] lib/openlanes/engine/extensions.rb:176
`Extensions#rounds` counts a grant with no `moves` key on every visit to that state, not "until the plan moves" as its comment says. The old code also counted only grants settled since this process started. On upgrade, every plan with a settled legacy round grant gets all of them back at once, and keeps them on every return to that state.
- Input: a plan with 2 legacy round grants on `building` (this plan's own `state.json` has some) is sent back from review to `building`.
- Expected: a fresh budget of `rounds:`.
- Actual: `rounds:` + 2.
- Suggested change: treat a grant with no `moves` as belonging to the visit its `settled_at` falls in, or as expired.

### F3 [minor] lib/openlanes/plans/rounds.rb:113
`Rounds#signed` compares ISO 8601 strings (`it["at"].to_s >= since`), which only orders correctly when both carry the same UTC offset. Across a DST change (`-07:00` against `-08:00`), or between a signer and an engine in different zones, a signature up to an hour old can fall either side of `since`.
- Input: a visit's first stage starts at `2026-11-01T01:30:00-07:00` and a signature is at `2026-11-01T01:10:00-08:00` (40 minutes later).
- Expected: it counts.
- Actual: it is excluded, because it sorts before `since` as a string.
- Suggested change: parse both with `Time.iso8601`.

## Frontend, round 2 (frontend-coder)

staff-reviewer's F1, F2 and F3 are all in `lib/`; none names a front-end file, and no inline review comment exists on the PR for `web/`. No front-end change was needed. Re-verified the front end after the last backend change, with `npm install` first because `@xyflow/react` and `@dagrejs/dagre` (already in `package.json`) were missing from this checkout's `node_modules`:

- `cd web && npx vitest run`: Test Files 64 passed (64), Tests 622 passed (622).
- `npx tsc --noEmit`: exit 0. `npx eslint src cypress`: exit 0.
- `npm run build` then `bin/web-e2e`: All specs passed, 58 tests, 58 passing, including `round-ledger.cy.ts` (2/2).
- The back-end integration proof (`restart_rounds_spec.rb`) is backend-coder's; see its round 5 entry above.

## Answers, round 6 (backend-coder)

No inline review threads on #246; the three findings above are answered here.

- F1 `fix`: failed starts back off and ask a person instead of parking silently. `Desk#failed_start_hold` (`lib/openlanes/engine/dispatcher/desk.rb`) holds an agent `30 s * 2^(n-1)` after its n-th failed start in a row and caps it at 3; a failed login is excused from that count (`Rounds::Count#except` = `Executor::AUTH_FAILURE`). At the cap `Extensions#stalled` raises one rounds request per run of failures; granting it lifts the cap (`Extensions#lifted_at` feeds `Rounds::Count#since`), across restarts too, since both read `state.json`. `Assign#idle_reason` adds `failed starts: <plan> <agent> (3 in a row; grant it a round to retry)` or `(retrying after a backoff)`. `CliPause` keeps its probe backoff across a release and resets it (`#clear`) only once an agent on that CLI spends something, so the expired-token loop slows down instead of spinning. Specs: `spec/openlanes/engine/dispatcher_rounds_spec.rb` (backoff, cap across restart, idle line, one request per run, grant lifts the cap), `spec/openlanes/engine/cli_pause_spec.rb`, `spec/openlanes/plans/rounds_spec.rb`.
- F2 `fix`: `Extensions#rounds` no longer counts a grant with no `moves`, which matches what the old engine did after any restart. `PlanState#settle_extension!` stamps `moves` on an old open request when it is answered, so that grant counts for the visit it is answered in and then expires. Specs: `spec/openlanes/engine/extensions_spec.rb`.
- F3 `fix`: `Rounds#signed` parses `started_at` and `at` with `Time.iso8601`, so the DST example counts; a malformed time is ignored. Spec: `spec/openlanes/plans/rounds_spec.rb`, "when the signature and the stage carry different UTC offsets".

### Checks, round 6 (backend-coder)

- `bundle exec rubocop`: 1002 files inspected, no offenses detected.
- `env -u OPENLANES_ADMIN_CREDENTIALS bundle exec rspec`: 6724 examples, 1 failure, coverage 99.15%. The failure was `spec/integration/resume_across_rounds_spec.rb:155`, which expected three back-to-back failed starts; with the backoff a one-shot run tries once. Expectation updated; `bundle exec rspec spec/integration/resume_across_rounds_spec.rb`: 6 examples, 0 failures. No library code changed after the full run.
- Focused: `bundle exec rspec spec/openlanes/plans/rounds_spec.rb spec/openlanes/engine/cli_pause_spec.rb spec/openlanes/engine/extensions_spec.rb spec/openlanes/engine/dispatcher_rounds_spec.rb`: 62 examples, 0 failures; `rounds.rb` 100%, `cli_pause.rb` 100%, `extensions.rb` 99%.
- No front-end change and no snapshot shape change this round.
