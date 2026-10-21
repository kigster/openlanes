# Contract: 022.00 Redis Outage Resilience

Owner: `luke-backend`. Partner: `rey-frontend`.

## Baseline

`bundle exec rspec` on clean `HEAD` (`7186635`), run 2026-10-17 outside the sandbox: `spec/openlanes/apps` plus `spec/openlanes/cli/app_spec.rb` give 112 examples, 30 failures. The same 30 fail on this branch. Files: `apps/ports_spec.rb` (1), `apps/probe_spec.rb` (1), `apps/restart_spec.rb` (4), `apps/runner_spec.rb` (9), `apps/supervisor_spec.rb` (11), `cli/app_spec.rb` (4). Root symptom: `Apps::Probe.ready?(closed_port)` returns true on this machine (`probe_spec.rb:42`), so something answers on ports the suite thinks are free. Every other spec passes (971 examples across `live`, `execution`, `engine`, 0 failures). No plan unit touches `lib/openlanes/apps/`.

Round 2, full suite on this branch: 3175 examples, 30 failures, 9 pending. The 30 are exactly the baseline above. The 9 pending all skip with `web/dist is missing`. A plain Ruby check confirms the cause is the machine: `Socket.tcp("127.0.0.1", p)` connects to a port `p` that was just bound and closed, so something on this host accepts connects on every closed local port.

This baseline conflicts with the implementation requirement that `bundle exec rspec` exits 0. Code in this plan cannot change it, so the plan is blocked on it (`blocked.md`, B1).

### D1 (decision) — Accept the 30 baseline failures

Answered:

- 2026-10-20
- By kig

The 30 failures in `spec/openlanes/apps` and `spec/openlanes/cli/app_spec.rb` are accepted as an environmental baseline for this plan. The host's listener on closed local ports is not fixed here, and the `apps` specs are not changed to skip. Completion of this plan is judged on every other spec passing and on the coverage gate, with these 30 recorded as known.

## Interfaces rey reads

No route is added or changed. `GET /api/board` and the `event: board` stream gain an optional `run.outage`:

| Field | Type | Meaning |
| :-- | :-- | :-- |
| `started_at` | ISO 8601 UTC string | this node's last heartbeat before the outage, or the first failure by clock |
| `ended_at` | ISO 8601 UTC string | the probe that got an answer |
| `seconds` | integer | `ended_at - started_at`, rounded |
| `measured_by` | `"heartbeat"` or `"clock"` | heartbeat when Redis still held one from within 15 s of the first failure |
| `reconciled_from` | `"redis"`, `"file"` or `null` | which copy of run state had the higher `seq`; null with neither |

`run.outage` is `null` until this run recovers from an outage, and keeps the last outage after that. Errors: none; a paused engine publishes nothing, so the page infers a live outage from snapshot age (plan.md, F1).

Built in `Live::OutageReport#to_h`, published by `Publisher#outage`, set by `Session#recover`.

## Back-end interfaces (built)

- `Live::Backoff.new(initial: 1.0, cap: 30.0, jitter: :full)`, `#delay(attempt, rand:)`.
- `Live::Outage`: `#trip!`, `#paused?`, `#due?`, `#probe!`, `#window`.
- `Execution::Control::PAUSE`, `.pause!`, `.resume!` (clears `PAUSE` only), `.paused?`.
- `RunRecord#reconcile` returns `:redis`, `:file` or nil.
- `Dispatcher#unavailable!(error)`, `#paused?`, `#outage`, `#live_store=`, `#on_recover { |window| }`, `backoff:` keyword. While paused: no dispatch, no before-tick hooks, no mail drain; reaping, control files, the clock and Ctrl-C still run. `probe_live` runs first in every tick.
- `Publisher#on_unavailable { |error| }`, `#outage=`. `Commands#call` trips the dispatcher on `Unavailable`.
- `Commands#call` rescues `NOGROUP` and makes its consumer group again on the next tick. This was the #59 crash (plan.md, Reproduction).
- `Config#backoff` from `.openlanes.yml` `redis.backoff.{initial,cap,jitter}`, the defaults when unset; `Runner.new(backoff:)` hands it to the dispatcher, and `RunWorkflow` passes `Config.current.backoff`.
- `Session#attach` wires `live_store`, `on_unavailable` and `on_recover`; `Session#recover(window)` logs `OutageReport#line` and sets `publisher.outage`.

## File ownership

- rey: `web/src/api/types.ts`, `web/src/shell/Header.tsx`, `Header.test.tsx`, `shell.css`, `web/src/api/fixtures/snapshot.json`, `snapshot-outage.json`.
- luke: everything under `lib/` and `spec/`, `README.md`, `.openlanes.coverage.yml`, this file, `openapi.yaml` (beside this file).
- Shared: none.

## Build order

B1 → B2, B3 → B4 → B5 → B6 → B7. F1 depends only on the wire shape above.

## Integration proof

`spec/openlanes/live/redis_outage_integration_spec.rb` (B6, 3 examples, passing): real `redis-server` on an ephemeral port, real `Store`, `Session`, `Publisher`, `Dispatcher`; kill Redis, assert pause and `PAUSE`; restart, assert the read-back snapshot carries `run.outage` with `seconds > 0`; restart with the data dir wiped, assert `reconciled_from: "file"`.

## Coverage gate

amended: the prompt asks for a `coverage:` section in `.openlanes.yml`, but this repo's `Config` rejects unknown keys there. The gate reads `.openlanes.coverage.yml` instead (`Coverage::Config::FILE`), which allows exactly `command`, `report`, `format` and `minimum`. Written as `bundle exec rspec`, `coverage/.resultset.json`, `simplecov`, 95. The full-suite run prints `Coverage: 97.86%`. The gate withholds while the 30 baseline failures stand, because it puts the command's own verdict first.

## Status, round 2

- [x] B1 reproduce #59 (`spec/openlanes/engine/redis_outage_spec.rb`; plan.md, Reproduction)
- [x] B2 backoff and outage (`backoff_spec.rb`, `outage_spec.rb`)
- [x] B3 `PAUSE` (`control_spec.rb`, `live_controls_spec.rb`)
- [x] B4 report and `run.outage` (`outage_report_spec.rb`, `run_record_spec.rb`, `snapshot_spec.rb`)
- [x] B5 dispatcher wiring (`spec/openlanes/engine/dispatcher_outage_spec.rb`)
- [x] B6 real-Redis integration spec (`spec/openlanes/live/redis_outage_integration_spec.rb`, `spec/support/redis_server.rb`)
- [x] B7 README "When Redis goes away", `redis.backoff` through `Config`, `Runner`, `RunWorkflow` (`spec/openlanes/config_backoff_spec.rb`)
- [x] `openapi.yaml`
- [x] `.openlanes.coverage.yml`
- [ ] `bundle exec rspec` exits 0: blocked on the 30 baseline failures
