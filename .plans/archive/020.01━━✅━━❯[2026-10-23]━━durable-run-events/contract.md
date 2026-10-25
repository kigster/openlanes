# Contract: 020.01 Durable Run Events

> [!NOTE]
>
> amended (2026-10-23, luke-backend, after D1): B1 was answered **b**, so the database sink and the Reports page belong in this pull request. The JSONL log and CLI sections below are as built and stay. The database half is in **## Database sink and Reports page (D1)** at the end, written before any code. It adds an HTTP surface, described in `openapi.yaml` beside this file.

Owner: `luke-backend`. HTTP surface: `GET /api/reports` (`openapi.yaml`).

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

## Database sink and Reports page (D1)

Written 2026-10-23 by `luke-backend`, after D1 and before any code. Where B2 (what the page reads) was never answered separately, this takes its recommended option: the page reads the database, and falls back to the JSONL log when no database is configured.

### Dependencies and configuration

- `openlanes.gemspec` gains `activerecord ~> 8.1` and `sqlite3 ~> 2.9`. `pg` is not a gem dependency: it is required only when the URL is PostgreSQL, and a missing `pg` fails with `OpenLanes::Error` saying `gem install pg`. Assumption: a solo install should not need libpq.
- `.openlanes.yml`, `events.database`: absent means no database, so the JSONL log is the whole record and persistence stays optional. `sqlite` means `<Events.dir>/../openlanes_development.sqlite3`. `postgresql` means `postgresql://localhost/openlanes_development`. Anything else must be a `sqlite3:` or `postgres(ql)://` URL. `OPENLANES_DATABASE_URL` overrides the file. Other values make `Config.parse` raise `OpenLanes::Error`. `events.database` without `events.enabled: true` is an error, because nothing would ever be written.

### Write path: an in-process pub/sub

`Events.emitter` returns an `Events::Bus` when a database is configured, and the existing `Sink` or `NullSink` otherwise. `Bus#record(...)` builds the event once (same `event_id` as today) and publishes it to its subscribers in order: the JSONL `Sink`, `Database::Recorder` (insert into `events`), and `Database::Tasks` (the projection into `tasks`). Every subscriber rescues `StandardError` to a warning, so a database outage costs a warning and still leaves the JSONL line. `Bus` answers the whole `Sink` interface (`record`, `with(run:)`, `enabled?`, `path`), so `Runner`, `Dispatcher`, `Publisher`, `PrOutcomes` and `Unblocker` do not change.

### Tables (migrations in `lib/openlanes/events/database/migrate/`)

| Table | Columns | Keys and rules |
| :--- | :--- | :--- |
| `events` | `id` bigint, `event_id` string(64), `kind`, `at` datetime(6), `project`, `plan` (`NNN.MM`), `plan_id` → `plans`, `run`, `agent`, `adapter`, `model`, `payload` json, `created_at` | `event_id` unique. A duplicate insert is skipped (`insert_all ... unique_by: :event_id`), which makes replay idempotent. Append-only: the model is `readonly?` once persisted, and nothing in the code updates or deletes rows. Indexes on `(kind, at)`, `plan` and `run`. |
| `plans` | `id` UUIDv7, `ordinal` (`NNN.MM`), `slug`, `title`, timestamps | `ordinal` unique. `title` is `Feature#titleize` of the slug, with no state emoji. |
| `agents` | `id` UUIDv7, `name`, `handles` json, `description` text (the agent file's Markdown body), `digest` string(64), timestamps | `name` unique. Upserted from `Agents.registry`, and a row is rewritten only when `digest` changes. |
| `tasks` | `id` UUIDv7, `plan_id` → `plans`, `run`, `round`, `agent`, `state` (`running`, `completed`, `blocked`, `failed`), `started_at`, `finished_at`, `last_event_id` | Unique on `(plan_id, run, round, agent)`. `agent_started` inserts `running`. `agent_finished` sets `completed` or `blocked` from the payload outcome, `failure` sets `failed`, and `run_finished` closes the run's leftover `running` rows as `failed`. In flight means `state = running`. |

UUIDv7 comes from `SecureRandom.uuid_v7`. It is stored as `uuid` on PostgreSQL and as `string(36)` on SQLite, and the migration picks the type from the adapter.

### Library interfaces (luke)

| Call | Returns | Errors |
| :--- | :--- | :--- |
| `Events.database_url(root:, config:, env:)` | `String` or `nil` | none |
| `Events::Database.connect(url)` | the `ActiveRecord` connection pool, on an abstract `Database::Record` base, so nothing global is touched | `OpenLanes::Error` when the URL is bad or `pg` is missing |
| `Events::Database.migrate(url)` | `Array<Integer>`, the versions applied. It creates the PostgreSQL database when missing, and the SQLite file and its directory | `OpenLanes::Error` |
| `Events::Database::Loader.new(url:).call(events:, tree:, registry:)` | `Loader::Result = Data.define(:inserted, :skipped, :plans, :agents)` | none per row; a failed batch raises `OpenLanes::Error` |
| `Events::Database::Reader.new(url:).events(since: nil, plan: nil)` | `Array<Event>`, oldest first, the same type `Log#events` returns, so `Events.report` is the one aggregation behind the CLI and the page | `OpenLanes::Error` when unreachable |
| `Events.source(root:, config:, env:)` | a `Database::Reader` when configured, else the `Log`. Both answer `#events` and `#skipped_lines` (always 0 for the database) | none |

### CLI (luke owns these two subcommands)

- `openlanes events migrate [-n]`: creates and migrates the configured database and prints the versions applied. Without a database configured it says so, names the key, and exits 1.
- `openlanes events load [--dir PATH] [-n]`: loads the JSONL node files into `events` and syncs `plans` from the tree and `agents` from the registry. It prints `Loader::Result`. Running it twice inserts nothing the second time.

### HTTP surface: `GET /api/reports` (route in `lib/openlanes/web/app.rb`, owned by luke)

- Query: `since` (ISO 8601, optional) and `plan` (`NNN.MM`, optional).
- 200 returns `{"source": "database" | "log", "generated_at": ISO 8601, "result": Report::Result#to_h}`, where `result` has exactly the fields in the `Events::Report::Result` table above, so the page and `events report --format json` show the same figures.
- 400 returns `{"error": "bad_param", "message": "..."}` for a malformed `since` or `plan`.
- 404 returns `{"error": "events_disabled", "message": "..."}` when `events.enabled` is not true. The message names the `.openlanes.yml` key.
- 503 returns `{"error": "database_unavailable", "message": "..."}` when a configured database cannot be reached. It does not fall back to the log silently.
- The schema is `openapi.yaml`.

### File ownership (D1 additions)

- luke: `openlanes.gemspec` (two dependencies), `Gemfile.lock`, `lib/openlanes/events/bus.rb`, `lib/openlanes/events/database.rb`, `lib/openlanes/events/database/*`, `lib/openlanes/events.rb` (`database_url`, `source`, `emitter`), `lib/openlanes/support/config.rb` (`events.database`), `lib/openlanes/cli/events/subcommands/{migrate,load}.rb` and their registration lines in `lib/openlanes/cli.rb`, the `/api/reports` route in `lib/openlanes/web/app.rb`, `openapi.yaml`, and their specs under `spec/openlanes/events/database/` and `spec/openlanes/web/reports_api_spec.rb`.
- rey: `web/src/**` (the nav button, the `/reports` route, the Reports page, its charts and tests), `web/cypress/**` (the Reports e2e), `lib/openlanes/cli/events/subcommands/report.rb` (`--source database|log`, default: database when configured), and `docs/events.md` (the database section).
- Shared: `lib/openlanes/cli.rb`. luke writes first, adding the `migrate` and `load` registrations; rey edits it after.

### Build order (D1)

B7 dependencies, connection, migrations → B8 `Bus`, `Recorder`, `Tasks` projection → B9 `Loader`, plans and agents sync, `migrate` and `load` → B10 `Reader`, `Events.source`, `/api/reports`. F3 (the nav button and the `/reports` route) can start now against `openapi.yaml`. F4 (the Reports page) waits on B10 only for the live check. F5 (`report --source`) waits on B10.

### Integration proof (D1)

`spec/integration/reports_api_spec.rb` (luke) writes through a real `Bus` into a temporary SQLite database: a `Runner` round with an injected executor, the same scenario as `events_report_spec.rb`. It then asserts that `GET /api/reports` through `rack-test` returns the same `result` that `exe/openlanes events report --format json --source database` prints as a subprocess. Nothing is stubbed except the executor and GitHub. rey's Cypress spec then loads `/reports` against a demo server seeded the same way, and checks that the page shows those figures and that the Board is gone.

### Amendments (D1)

- amended: there is no separate Bus emitter. `Sink.new(bus:)` writes its JSONL line, then calls `Bus#publish(event)`, and `Sink#with(run:)` keeps the bus. `Events.emitter` still returns a `Sink` or a `NullSink`, so the callers and the interface are unchanged. The reason: one place builds the event and its id.
- amended: `Events.emitter` migrates the database when it builds the bus. If the database cannot be opened, it warns once (`recording to the JSONL log only`) and returns a sink with no bus. The reason: an unmigrated table would cost one warning per event.
- amended: `plans.slug` and `plans.title` are nullable. An event can name a plan before its folder is known, for example a plan the tree no longer has. `Recorder` fills both from the tree when the tree finds the folder.
- amended: `events.plan_row_id` and `tasks.plan_row_id` reference `plans`. The column is not `plan_id`, because `events.plan` already holds the `NNN.MM`.
- amended: the 404, 400 and 503 logic lives in `Web::Reports#call(since:, plan:)` and returns `[status, body]`. The route only passes the parameters in. `Web::Context#reports` lets a test inject one.
- amended: `Log#events(since: nil, plan: nil)` and `Log#source` (`"log"`) were added, so `Events.source` returns either reader behind one interface.
- amended: `events migrate` and `events load` exit 78 when no database is configured (the message names `events.database` and `OPENLANES_DATABASE_URL`) and 69 when the database refuses. `load` takes `--log-dir PATH` for node files copied from another machine, and migrates the database before loading. `Log#all` returns every deduped event; `Loader#call(events:, tree:, registry:)` is as specified, and an agent row is rewritten when the SHA-256 of its `agents/*.md` file changes.
- amended: the integration proof does not wait for F5 `--source`. It records one run through the real emitter into both stores, then asserts that `GET /api/reports` (reading the database) equals `exe/openlanes events report --format json` (a subprocess reading the JSONL log). The same figures from two stores is the stronger check, and no executor double is needed: the events are recorded directly through `Sink#record`.

### Status (D1), 2026-10-23, luke round 2

- Done: every back-end unit, B7 to B10.
- Specs: `spec/openlanes/events/database_spec.rb`, `spec/openlanes/events_emitter_spec.rb`, `spec/openlanes/events/bus_spec.rb`, `spec/openlanes/events/database/{url,recorder,tasks,loader}_spec.rb`, `spec/openlanes/cli/events/{migrate,load}_spec.rb`, `spec/openlanes/web/reports_spec.rb`, `spec/openlanes/web/reports_api_spec.rb` (the route, through rack-test), `spec/integration/reports_api_spec.rb` (the integration proof), and the `events.database` examples in `spec/openlanes/config_spec.rb`.
- PostgreSQL, checked by hand on 2026-10-23 against local PostgreSQL 18 (scratch database `openlanes_luke_check`, dropped afterwards). `Database.migrate` created the database and applied 4 migrations, and a second run applied 0. `plans.id` is a native `uuid`. Recording one event twice left 1 row, `tasks` showed `running`, and `Reader#events` returned 1. The suite runs on SQLite only, because `pg` is not a gem dependency.
- Baseline 2026-10-23, before any D1 code: 4265 examples, 4 failures (`spec/integration/mail_round_trip_spec.rb:119`, `spec/integration/verification_spec.rb:138`, `:160` and `:180`). All 4 pass when run alone, so they are timing-sensitive under the full suite. No D1 unit touches those files.
- After B7, B8 and B10: `bundle exec rspec` → 4307 examples, 0 failures, 45 pending. `bundle exec rubocop` → 607 files, no offenses.
- Round 2, after B9: `bundle exec rspec` → 4327 examples, 0 failures, 45 pending, exit 0. An earlier full run in this round failed once, at `spec/openlanes/cli/app_spec.rb:78`, a two-process app test. It passes alone and alongside the D1 specs on the same seed, so it is timing-sensitive. `bundle exec rubocop` → 615 files, no offenses, exit 0.
