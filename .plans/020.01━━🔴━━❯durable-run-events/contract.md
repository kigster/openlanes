# Contract: 020.01 Durable Run Events

Owner: `luke-backend`. No HTTP surface, so no `openapi.yaml`.

## Baseline

`bundle exec rspec` before any change, 2026-10-16: 1 failure, `spec/openlanes/apps/supervisor_spec.rb:133` (port-mismatch example, unrelated to events). No file under `## Backend` touches it.

## Interfaces rey calls (F1)

### `OpenLanes::Events` facade (`lib/openlanes/events.rb`)

| Call | Returns | Errors |
| :--- | :--- | :--- |
| `Events.dir(root:, config: Config.current, env: ENV)` | `String`, absolute: `events.dir`, else `${XDG_STATE_HOME:-~/.local/state}/openlanes/<basename>-<6 hex>/events` | none |
| `Events.log(dir)` | `Events::Log` | none; a missing dir reads as empty (`#exist?` false) |
| `Events::Log#events` | `Array<Event>`, deduped by `event_id`, oldest first | never raises on bad lines |
| `Events::Log#skipped_lines` | `Integer`, lines that were not events | none |
| `Events::Log#files` | `Array<String>`, the `*.jsonl` node files | none |
| `Events.report(events, skipped_lines: 0)` | `Events::Report::Result` | none |
| `Config#events_enabled` / `Config#events_dir` | `Boolean` (default `false`) / `String` or `nil` | `Config.parse` raises `OpenLanes::Error` on a malformed `events:` |

### `Events::Report::Result` fields (frozen; renaming needs mail)

| Field | Type | Meaning |
| :--- | :--- | :--- |
| `runs` | Integer | unique agent runs `(plan, round, agent)` that finished |
| `completion_rate` | Float 0..1 or nil | finished `Completed` / `runs`; nil when `runs` is 0 |
| `blocks` | Integer | every `block_raised` |
| `runs_needing_feedback` | Integer | unique agent runs with at least one block |
| `intervention_rate` | Float 0..1 or nil | `runs_needing_feedback` / runs started; nil when none |
| `time_to_answer` | Hash `{count:, median_s:, max_s:}` | seconds; `median_s`/`max_s` nil when `count` is 0 |
| `pr_outcomes` | Hash `{"opened", "reviewed", "merged", "closed" => Integer}` | each PR counted once per outcome |
| `usage_by_run` | Array of `Report::Usage` | grouped by `[run, adapter, model]` |
| `usage_by_model` | Array of `Report::Usage` | grouped by `[adapter, model]`, `run` is nil |
| `skipped_lines` | Integer | from `Log#skipped_lines` |

`Report::Usage = Data.define(:run, :adapter, :model, :invocations, :input_tokens, :output_tokens, :cost_usd, :estimated, :incomplete)`. `cost_usd` is nil when any spend in the group was unpriced (codex, pi): render `unknown`, never `$0`. `estimated: true` means render `(est.)`. `incomplete: true` means a claude run spawned sub-agents whose spend the figure leaves out. Never sum rows across adapters.

`Result#to_h` is JSON-ready (usage rows as hashes); `--format json` prints it.

### Event log format (for docs, F2)

One JSON object per line, `<dir>/<node id>.jsonl`. Keys: `event_id kind at project plan run agent adapter model payload`. Kinds and their allowlisted payload keys: `Events::Event::PAYLOAD_KEYS`. The only non-id string is `failure`'s `error_class`, cut to 120 characters. No prompt, transcript, answer text or `total_cost_usd` is ever stored.

## File ownership

- luke: `lib/openlanes/events.rb`, `lib/openlanes/events/*`, `lib/openlanes/support/config.rb` (`events:` key), `lib/openlanes/engine/{runner,dispatcher,pr_outcomes}.rb`, `lib/openlanes/vcs/publisher.rb`, `lib/openlanes/lifecycle/unblocker.rb`, `spec/openlanes/events/*`, `spec/openlanes/config_spec.rb` (events examples), `spec/fixtures/events/*`.
- rey: `lib/openlanes/cli/events/*`, `lib/openlanes/cli.rb` (registration), `lib/openlanes/presentation/events_report.rb`, `README.md` (`## Configuration`), `docs/events.md`, their specs, `spec/integration/events_report_spec.rb`.
- Shared: none.

## Build order

B1, B2 → B3, B5 → B6 → B4 → F1. F2 after B3.

## Integration proof

`spec/integration/events_report_spec.rb` (rey, F1): real `Runner` round with an injected executor, real `Unblocker`, `PrOutcomes` with the `GitHub` double, then `exe/openlanes events report --format json` as a subprocess. Nothing else stubbed.

## Amendments

- amended: `time_to_answer` pairs a block with the next `human_answered` on the same **plan**, not the same `(plan, round, agent)`. The unblocker drains a plan's questions and cannot tell which agent's round asked them; a blocked plan runs no other agent meanwhile.
- amended: `human_answered` carries `block` (`B<n>`) and `answered_at`; `round` stays empty for the same reason.
- amended: PR events and `human_answered` are keyed without the run id (`Sink#record(..., once: true)`), so two runs noticing the same merge dedupe to one.
- amended: `Runner.new(events:)`, `Publisher.new(events:)`, `PrOutcomes.new(events:)`, `Unblocker.new(events:)` each default to `Events::NullSink.new`. `RunWorkflow#events` builds the emitter once per run (null on `--dry-run`). For the integration proof: pass a `Sink` (or set `events: { enabled: true }` plus `XDG_STATE_HOME`) and drive `Runner#call`.
- amended: `Runner#call` mints the run id (16 hex) and records `run_started`/`run_finished`; `Dispatcher` records `agent_started`, `agent_finished` (with `Usage`), `block_raised` (payload `blocks`: open `## B<n>` count) and `failure` (`error_class` only; `AttemptFailed` when no exception).

## Status

- Done: B1, B2, B3, B4, B5, B6, with specs: `spec/openlanes/events/*`, `spec/openlanes/engine/events_emit_spec.rb`, `spec/openlanes/config_spec.rb` (events).
- After the last unit: `bundle exec rspec` 3222 examples, 0 failures, 9 pending; `bundle exec rubocop` 459 files, no offenses. The baseline failure (`supervisor_spec.rb:133`) did not recur.
- Not done by luke: F1, F2 (rey). The integration proof is F1's.
- 2026-10-17 rerun: `bundle exec rspec` 3224 examples, 31 failures, all port-dependent (`spec/openlanes/apps/*`, `spec/openlanes/cli/app_spec.rb`). Cause is the machine: loopback connects to unused ports succeed, so `Apps::Ports` sees every port taken. Reproduces on pristine `HEAD`; no events file involved. Rubocop clean. Blocked (technical) on the "rspec exits 0" requirement: `blocked.md` B1.
- 2026-10-20: B1 answered (rebase onto main). Applied main's `ff03ca48` port-detection fix verbatim, since agents cannot rebase. `bundle exec rspec` → 3225 examples, 0 failures, 9 pending (web/dist missing). `bundle exec rubocop` → 460 files, no offenses. Integration proof green, see `pull-requests.md`.
