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

### Baseline cleared (round 3, 2026-10-21)

amended: the B1 answer was "rebase onto main", but this branch's `HEAD` (`7186635`) is still behind `origin/main` and agents may not rebase. The cause was not the host: behind Little Snitch, `Socket.tcp` with `connect_timeout` returns a socket for a refused connect, and only `getpeername` raises `EINVAL`. `origin/main` already fixed that in `ff03ca48`. This branch takes the same fix, so the later rebase applies cleanly: `lib/openlanes/apps/probe.rb` and `lib/openlanes/apps/ports.rb` are copied verbatim from `origin/main`, and the `connectable?` helper in `spec/openlanes/apps/supervisor_spec.rb` and `spec/openlanes/cli/app_spec.rb` is replaced with main's one-line version. Full suite: 3175 examples, 0 failures.

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

amended (round 4): this list used to name a `Live::Backoff`, `Config#backoff`, `redis.backoff.*` keys, `Runner.new(backoff:)`, `Dispatcher#unavailable!` and `#probe_live`, `Publisher#on_unavailable`, and a `NOGROUP` rescue in `Commands#call`. None of them exist on this branch. What main already had, and what this branch adds on top, follows.

On `main` before this branch, not built here:

- `Live::Outage` (`ec5b95eb`): 10 s grace, then `Execution::Control.pause!` (`PAUSE`), Fibonacci probes of 1, 1, 2, 3, 5, 8 … s, `Control.resume!` (`RESUME`) when Redis answers, and shutdown after `redis_outage_hours`. amended (round 5): this branch adds `Outage.new(initial:, cap:, jitter:, random:)` and the `.openlanes.yml` section `redis_backoff:` that feeds it; each gap is `min(fib * initial, cap)`, times `random.rand` under jitter.
- The #59 fix (`14a7f439`): `Store#xreadgroup` raises `GroupMissing` on `NOGROUP`, and `Commands` makes its consumer group again.

Built on this branch:

- `Live::Outage::Window` (`started_at`, `ended_at`, `seconds`), `Outage#window`, `Outage#on_resume { |window| }`.
- `RunRecord#reconcile` returns `:redis`, `:file` or nil, sharing `newest` with `restore`.
- `Live::OutageReport.new(store:, keys:, node:, window:, reconciled_from:)`, `#to_h` (the `run.outage` shape above), `#line`.
- `Snapshot` takes `outage:`, `nil` by default; `Publisher#outage` / `#outage=` carries it into every snapshot from then on.
- `Session.new(outage:)`; `Session#attach` registers `outage.on_resume`; `Session#recover(window)` logs `OutageReport#line` and sets `publisher.outage`.

## File ownership

- rey: `web/src/api/types.ts`, `web/src/shell/Header.tsx`, `Header.test.tsx`, `shell.css`, `web/src/api/fixtures/snapshot.json`, `snapshot-outage.json`.
- luke: everything under `lib/` and `spec/`, `README.md`, `.openlanes.coverage.yml`, this file, `openapi.yaml` (beside this file).
- Shared: none.

## Build order

B1, B2 → B4 → B5 → B6 → B7. B3 is main's. F1 depends only on the wire shape above.

## Integration proof

`spec/openlanes/live/redis_outage_integration_spec.rb` (B6, 3 examples, passing): real `redis-server` on an ephemeral port, real `Store`, `Session`, `Publisher`, `Dispatcher`. Example 1: a snapshot reaches the real Redis. Example 2: kill Redis, assert pause and `PAUSE`; restart it, assert the read-back snapshot carries `run.outage` with `seconds > 0`, `measured_by: "heartbeat"`, `reconciled_from: "redis"`. Example 3: restart with the data dir wiped, assert `reconciled_from: "file"`.

`spec/openlanes/engine/redis_outage_spec.rb` (B1, 1 example) is a real-Redis regression test for main's #59 fix `14a7f439`; it passes on `main` without this branch.

## Coverage gate

amended: the prompt asks for a `coverage:` section in `.openlanes.yml`, but this repo's `Config` rejects unknown keys there. The gate reads `.openlanes.coverage.yml` instead (`Coverage::Config::FILE`), which allows exactly `command`, `report`, `format` and `minimum`. Written as `bundle exec rspec`, `coverage/.resultset.json`, `simplecov`, 95. The full-suite run prints `Coverage: 97.86%`. The gate withholds while the 30 baseline failures stand, because it puts the command's own verdict first.

## Status, round 4

amended: the round 2 list claimed `backoff_spec.rb`, `config_backoff_spec.rb`, a `redis.backoff` key and a `NOGROUP` rescue of our own. None are on this branch.

- [x] B1 #59 regression against real Redis (`spec/openlanes/engine/redis_outage_spec.rb`, 1 example; the fix is main's `14a7f439`)
- [x] B2 `Outage::Window`, `#window`, `#on_resume` (`outage_spec.rb`)
- [x] B2 configurable backoff: `redis_backoff.{initial,cap,jitter}`, default 1 s, 30 s (`Outage::MAX_GAP`), full jitter (`outage_spec.rb`, `config_spec.rb`). amended (round 5): built after hansolo's 2/2; it was listed as not built
- [x] B3 `PAUSE`: on main already (`ec5b95eb`), nothing built here
- [x] B4 report and `run.outage` (`outage_report_spec.rb`, `run_record_spec.rb`, `snapshot_spec.rb`)
- [x] B5 session wiring (`spec/openlanes/engine/dispatcher_outage_spec.rb`)
- [x] B6 real-Redis integration spec (`spec/openlanes/live/redis_outage_integration_spec.rb`, `spec/support/redis_server.rb`)
- [x] B7 README: one "A lost Redis" paragraph, the duplicate section folded in
- [x] `openapi.yaml`
- [x] `.openlanes.coverage.yml`
- [x] `bundle exec rspec` exits 0
