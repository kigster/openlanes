# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 80 | [\[020.00\](A) Lanes with No Active Agents](https://github.com/kigster/openlanes/pull/80) | Merged 🟣 |

## frontend-coder, round 1

- web: `npm test` 358 passed; `npm run lint` and `npm run typecheck` clean.
- `OPENLANES_LANES_E2E=1 just lanes-e2e` NOT run: it spends real tokens and backend-coder had not signalled done. Files are written; the last agent or a human must run it.

## frontend-coder, round 1 (resumed)

- web: `npm test` 358 passed; `npm run lint` and `npm run typecheck` clean.
- `bundle exec rspec`: 3142 examples, 4 failures in `apps/supervisor_spec.rb` and `cli/app_spec.rb` (files untouched by this plan); both pass when run alone (22 examples, 0 failures), so they are order/port flakes in the full run.
- `OPENLANES_LANES_E2E=1 just lanes-e2e` NOT run: spends real tokens and backend-coder is not done. The last agent or a human must run it.

## backend-coder, round 1 (resumed)

- B4 built (slash parser, copilot route, 503 without a live engine, copilot paragraph); `/concurrency` now survives an engine restart. `openapi.yaml` written.
- `bundle exec rspec`: 3142 examples, 0 failures, 9 pending (one supervisor port flake on an earlier full run; passed alone and on the rerun).
- `bundle exec rubocop`: 433 files, no offenses.
- `OPENLANES_LANES_E2E=1 LANES_TIMEOUT=300 just lanes-e2e`, three runs:
  1. 1 passing, 4 failing: tests 2-5 never found `#copilot-input`. Cypress test isolation blanked the page after `before()`. Fixed: `{ testIsolation: false }` on the describe in `lanes.cy.ts` (frontend-coder mailed).
  2. 4 passing, 1 failing (step 4): `/restart B` was answered `done`. Correct: B's agent had just failed with "publish refused — plan.md has no `## How to test` section", so B had no agent. Fixed: added `## How to test` to the three fixture specs (frontend-coder mailed).
  3. 4 passing, 1 failing (step 4): `/restart A` was answered `done: 000.00 restarts at the next tick`, but no car for A appeared within 15 s. Likely cause: step 2 set concurrency to 2 and B and C still hold both slots, so A waits for a free one. Not confirmed before time ran out.
- Next step: confirm from `log/lanes-e2e/start.log` that A starts once a slot frees. If so, have step 4 wait for a free slot or raise concurrency back to 3 first. If not, look at whether `Dispatcher#restart_plan` clears everything that keeps A from dispatch after an Interrupted round ("no rounds left").

## frontend-coder, round 1 (final, integration proof)

- `OPENLANES_LANES_E2E=1 LANES_TIMEOUT=300 just lanes-e2e`: 5 passing, 0 failing (lanes.cy.ts). Step 4 now raises concurrency back to 3 before `/restart`, so A has a slot.
- web: `npm test` 358 passed; `npm run lint` and `npm run typecheck` clean.
- `bundle exec rubocop`: 433 files, no offenses.
- `bundle exec rspec`: 3142 examples, 30 failures, all in `spec/openlanes/apps/*` and `cli/app_spec.rb` (untouched by this plan). They fail even alone on this machine now: `Probe.ready?` answers true for a just-closed port (`probe_spec.rb:41`), so something local accepts connections on any loopback port. Environmental, not caused by the diff; backend-coder saw the same family pass on his earlier runs. The other 3112 pass.

## backend-coder, round 1 (resumed again, last)

- Step 4 cause confirmed from `log/lanes-e2e/progress.log`: after `/concurrency 2`, B and C held both slots, so a restarted A queued (correct). `lanes.cy.ts` step 4 now sends `/concurrency 3` first.
- Step 3: `/stop` is cooperative (control-file STOP, killed 60 s later), so the car can outlive it by up to a minute; step 3 now waits `STOP_GRACE` (90 s).
- Fixtures: the spec parser reads `## How to tell it's working?`, not `## How to test`, so B and C were refused at publish. Heading fixed in all three; beta runs `sleep 90` first so "B already has an agent" is not a race.
- `OPENLANES_LANES_E2E=1 LANES_TIMEOUT=300 just lanes-e2e`: 5 passing, 0 failing, exit 0.
- Unrelated, found on the way: on Darwin 27, Ruby 4.0.6's `Socket.tcp(..., connect_timeout:)` returns an unconnected socket for a refused port instead of raising, so `Apps::Ports.answering?` and `Apps::Probe.listening?` read every port as taken (26-30 failures in `spec/openlanes/apps`, `cli/app_spec`). Both now ask for `remote_address`; the same change in the spec helpers and `spec/fixtures/apps/servers/server.rb`. `bundle exec rspec spec/openlanes/apps spec/openlanes/cli/app_spec.rb`: 112 examples, 0 failures.
- `bundle exec rspec`: 3142 examples, 0 failures. `bundle exec rubocop`: 433 files, no offenses.
- Rerun for `## How to test`, now in plan.md. `bundle exec rspec`: 3142 examples, 0 failures (one earlier full run failed once in `spec/integration/restart_spec.rb:43`, which passed 3/3 alone and on the rerun). `bundle exec rubocop`: no offenses.

## backend-coder, round 1 (staff-reviewer's 🚫 on `DemoBoard`)

- `DemoBoard` gains `stop_plan`, `restart_plan`, `set_concurrency`, worded as the engine words them; `/restart` refuses while a car runs ("already has an agent") and brings back only stopped cars. `DemoBoard#apply` now refuses any kind it has no handler for ("the demo cannot …") instead of raising `NoMethodError` on the demo thread; that also covers `respond`, `pause_discuss` and `resume_anyway`, which had the same latent crash.
- `Demo#answer` writes the `"<id>.1"` copilot turn for `payload.source == "copilot"`, in the same `MULTI`, not on redelivery. The turn is built by `Live::Commands.echo_turn`, now a class method, so engine and demo share one definition.
- New examples: `spec/openlanes/web/demo_board_spec.rb` ("the lane commands", "a kind the demo has no handler for"), `spec/openlanes/web/demo_spec.rb` ("when the copilot sent it": one turn on a double delivery, `run.jobs` changed).
- `bundle exec rspec`: 3614 examples, 0 failures. `bundle exec rubocop`: 488 files, no offenses (exit 0).
