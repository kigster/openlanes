# Plan 020.01: Durable Run Events

> [!NOTE]
>
> **As built, restored 2026-10-23 by `luke-backend`.** The previous `plan.md` was deleted in `41b53908` and re-created empty, which `hansolo-reviewer` rejected (finding 2): the plan described neither the diff nor the new direction. The units below are that deleted plan, unchanged, because they are exactly what #105 ships: an opt-in JSONL event log and `openlanes events report`.
>
> **D1 (2026-10-23):** B1 was answered **b**, so the database direction belongs in this pull request. That is Research Q2 (ActiveRecord on SQLite or PostgreSQL, with the tables `events`, `agents`, `plans` and `tasks`) and the Goal (a nav button and a Reports page). Its units are B7 to B10 under `## Backend` and F3 to F5 under `## Frontend`, and their interfaces are in `contract.md`, in **Database sink and Reports page (D1)**.

Builds the opt-in, append-only JSONL event log from `spec.md` (In scope 1 to 11) and the `openlanes events report` command that reads it. One pull request, eight units.

## Decisions taken while planning

- **Sink location.** Plan 021.00 is still in research. Its recommendation is `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<6 hex of sha256(root)>/`, matching `apps/ports.rb` and `progress_log.rb`. This plan uses that default, under an `events/` subdirectory, behind one resolver (`Events::Location`), so 021.00 changes a single method if it decides otherwise. `.openlanes.yml` can override the directory.
- **Config key.** `.openlanes.yml` gains `events: { enabled: false, dir: <path> }`. Absent or `enabled: false` means the null sink, and no file or directory is created.
- **Run id.** No run id exists today (`engine/state_file.rb:137` keeps only pid, root and `started_at`). `Runner` mints one per `call`: a digest of node name and run start. It is an identifier, not text.
- **Unique run for block metrics.** `(plan, round, agent)`, per spec open question 6. A re-block after an answer is a new block on the same unique run.
- **Usage across adapters.** Reported per adapter, never summed across adapters (spec open question 9). Cost: `estimated: true` on every computed figure, `null` for codex and pi.
- **Front end means the CLI here.** There is no web work. `rey-frontend` owns the command, its renderer and the docs, per the spec's own split.

## Order and dependencies

```mermaid
flowchart LR
  B1[B1 event model and identity] --> B3[B3 sink, location, config]
  B1 --> B5[B5 log reader and aggregates]
  B2[B2 usage mapping] --> B4
  B3 --> B6[B6 PR and answer emits]
  B6 --> B4[B4 engine emits and wiring]
  B5 --> F1[F1 events report command + integration check]
  B4 --> F1
  B3 --> F2[F2 docs]
```

Sequence: B1 and B2 in parallel; then B3 and B5 in parallel; then B6; then B4; then F1. F2 can start once B3 has fixed the config key. B4 and B6 are sequential because B4 constructs the classes B6 changes and passes them the `events:` keyword B6 adds.

Pair contract (spec, "Back end / front end"): `luke-backend` mails `rey-frontend` the field names of `Events::Report::Result` (B5) before F1 starts coding. Neither side renames a field without mail.

## Backend

### B1 Event model and identity

- **Discipline:** back end.
- **Owns:** `lib/openlanes/events/event.rb`, `lib/openlanes/events/identity.rb`, `spec/openlanes/events/event_spec.rb`, `spec/openlanes/events/identity_spec.rb`.
- **Must not touch:** every file owned by another unit; in particular `lib/openlanes/events.rb` (B3).
- **Depends on:** nothing.
- **Shape:** `Events::Event = Data.define(:event_id, :kind, :at, :project, :plan, :run, :agent, :adapter, :model, :payload)`. `Event::KINDS`: `run_started`, `run_finished`, `agent_started`, `agent_finished`, `block_raised`, `human_answered`, `pr_opened`, `pr_reviewed`, `pr_merged`, `pr_closed`, `failure`. `Event::PAYLOAD_KEYS`, one allowlist per kind; constructing an event with a key outside it raises. The only string payload that is not an id is `failure`'s `error_class`, bounded in length. `Event#to_h` and `Event.from_h` round-trip JSON. `Identity.event_id(node:, checkout:, plan:, round:, agent:, invocation_start:, kind:, seq:)` returns the SHA-256 hex.
- **Done when:** `event_spec.rb` builds every kind and asserts its fields, and asserts the serialised key set of every kind against the allowlist (spec item 10); `identity_spec.rb` shows the same inputs give the same id and any one changed input gives a different one (spec item 3).

### B2 Usage mapping

- **Discipline:** back end.
- **Owns:** `lib/openlanes/events/usage.rb`, `spec/openlanes/events/usage_spec.rb`.
- **Must not touch:** `lib/openlanes/execution/transcript.rb`, `lib/openlanes/adapters/*`, `lib/openlanes/live/meter.rb` (read only).
- **Depends on:** nothing.
- **Shape:** `Events::Usage = Data.define(:adapter, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens, :cost_usd, :estimated, :incomplete)`, built by `Usage.from(adapter:, model:, totals:, subagents_spawned: 0)`. Claude: tokens from the `result` accounting, cost from `Model#cost` with `estimated: true`, `incomplete: true` when sub-agents spawned. Codex and pi: tokens read defensively (nil when absent), `cost_usd: nil`. `total_cost_usd` is never read.
- **Done when:** `usage_spec.rb` has one example per adapter, a codex and a pi example asserting cost is `nil` and not `0`, and a claude example flagging a sub-agent run `incomplete` (spec item 8).

### B3 Sink, location and config key

- **Discipline:** back end.
- **Owns:** `lib/openlanes/events.rb` (facade), `lib/openlanes/events/sink.rb`, `lib/openlanes/events/null_sink.rb`, `lib/openlanes/events/location.rb`, `lib/openlanes/support/config.rb` (the `events:` key only), `spec/openlanes/events/sink_spec.rb`, `spec/openlanes/events/location_spec.rb`, `spec/openlanes/support/config_spec.rb` (new examples only).
- **Must not touch:** `lib/openlanes/live/*`, `lib/openlanes/engine/*`.
- **Depends on:** B1.
- **Shape:** `Events.emitter(root:, config:, node:)` returns a `Sink` or the `NullSink`. `Sink#emit(event)` appends one JSON line to `<dir>/<node.id>.jsonl` with a single `O_APPEND` write, creates the directory on first write, and rescues every `StandardError` to a warning: it never raises and never touches Redis. `Location.dir(root:, config:)` is the only place that knows the default path. Config parses `events.enabled` (boolean) and `events.dir` (absolute path) and fails on anything else.
- **Done when:** `sink_spec.rb` writes events and reads them back, shows the null sink creates no file or directory (spec items 4 and 5), shows a write still lands when a `Live::Store` double raises on every call (spec item 6), and shows an unwritable directory produces a warning, not an exception; `location_spec.rb` covers `XDG_STATE_HOME` set, unset and relative; `config_spec.rb` covers the key present, absent and malformed.

### B4 Engine emits and wiring

- **Discipline:** back end.
- **Owns:** `lib/openlanes/engine/runner.rb`, `lib/openlanes/engine/dispatcher.rb`, `spec/openlanes/engine/events_emit_spec.rb`.
- **Must not touch:** `lib/openlanes/engine/pr_outcomes.rb`, `lib/openlanes/vcs/publisher.rb`, `lib/openlanes/lifecycle/unblocker.rb` (B6), `lib/openlanes/live/*`.
- **Depends on:** B2, B3, B6.
- **Shape:** `Runner` mints the run id and builds the emitter once through `Events.emitter`; emits `run_started` and `run_finished`. `Dispatcher` emits `agent_started` in `start`; `agent_finished` (with `Usage`) and `block_raised` (when the agent signed Blocked) in `settle`; and `failure` with the error class when an attempt fails or the boundary check rejects it. It passes `events:` to the `PrOutcomes`, `Lifecycle::Unblocker` and `Vcs::Publisher` it constructs. Every emit is fire-and-forget; no emit can fail or stall a tick.
- **Done when:** `events_emit_spec.rb`, on a real `.plans` tree from `PlansFixture` with an injected executor (as `spec/openlanes/engine/dispatcher_spec.rb` does), shows one round produces `run_started`, `agent_started`, `agent_finished`, `run_finished`; a blocking agent adds `block_raised`; a failing attempt adds `failure` carrying only `error_class`; and with events disabled the run creates no file (spec item 2).

### B5 Log reader and aggregates

- **Discipline:** back end.
- **Owns:** `lib/openlanes/events/log.rb`, `lib/openlanes/events/report.rb`, `spec/openlanes/events/log_spec.rb`, `spec/openlanes/events/report_spec.rb`, `spec/fixtures/events/` (fixture node files).
- **Must not touch:** `lib/openlanes/events.rb` (B3: add facade methods after B3 lands), anything under `lib/openlanes/cli/` or `lib/openlanes/presentation/`.
- **Depends on:** B1.
- **Shape:** `Log.new(dir:)#events` reads every `*.jsonl` in the directory, skips malformed lines with a count, and dedupes by `event_id`. `Report.new(events)#call` returns `Report::Result = Data.define(:runs, :completion_rate, :blocks, :runs_needing_feedback, :intervention_rate, :time_to_answer, :pr_outcomes, :usage_by_run, :usage_by_model, :skipped_lines)`. `time_to_answer` pairs each `block_raised` with the next `human_answered` on the same `(plan, round, agent)`. Usage groups are keyed by adapter as well as model and never summed across adapters; a group containing any estimate is marked estimated.
- **Done when:** `report_spec.rb` with two node files holding one duplicate gives the expected numbers (spec item 9), and a fixture of 3 blocks over 2 unique runs reports 3 and 2 (spec item 7); `log_spec.rb` covers dedupe and a malformed line.

### B6 PR and human-answer emits

- **Discipline:** back end.
- **Owns:** `lib/openlanes/engine/pr_outcomes.rb`, `lib/openlanes/vcs/publisher.rb`, `lib/openlanes/lifecycle/unblocker.rb`, `spec/openlanes/events/pr_and_answer_emit_spec.rb`.
- **Must not touch:** `lib/openlanes/engine/dispatcher.rb`, `lib/openlanes/engine/runner.rb` (B4), `lib/openlanes/vcs/github.rb` (read only; it is the seam the spec doubles).
- **Depends on:** B3.
- **Shape:** each class takes `events:` defaulting to the `NullSink`. `Publisher` emits `pr_opened` with the PR number. `PrOutcomes` emits `pr_reviewed`, `pr_merged` or `pr_closed` only when it actually applies a change, so the watch re-asking every 15 seconds does not multiply events (and `event_id` dedupes anything that slips through). `Unblocker` emits `human_answered` per drained question, carrying the block id and answer time, never the answer text.
- **Done when:** `pr_and_answer_emit_spec.rb`, on `PlansFixture` trees with the `GitHub` double, shows each PR kind emitted once when an outcome is applied twice, and `human_answered` emitted per answered `B<n>` with no answer text in the payload (spec item 2).

### B7 Database dependencies, connection and migrations (D1)

- **Discipline:** back end.
- **Owns:** `openlanes.gemspec` (`activerecord`, `sqlite3`), `Gemfile.lock`, `lib/openlanes/events/database.rb`, `lib/openlanes/events/database/record.rb`, `lib/openlanes/events/database/url.rb`, `lib/openlanes/events/database/migrate/*.rb`, `lib/openlanes/support/config.rb` (`events.database` only), `spec/openlanes/events/database/{database,url}_spec.rb`, `spec/openlanes/config_spec.rb` (the new examples only).
- **Depends on:** B3.
- **Shape:** see contract, "Dependencies and configuration" and "Tables". `Database.connect(url)` connects an abstract `Record` base and never `ActiveRecord::Base`. `Database.migrate(url)` runs the four migrations through `ActiveRecord::MigrationContext`.
- **Done when:** a spec migrates a temp SQLite file and finds the four tables with their unique indexes; `url_spec.rb` covers `sqlite`, `postgresql`, an explicit URL, the env override and a malformed value; the config specs show `events.database` without `enabled: true` refused.

### B8 Bus, recorder and tasks projection (D1)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/events/bus.rb`, `lib/openlanes/events/database/{event_row,plan_row,agent_row,task_row,recorder,tasks}.rb`, `lib/openlanes/events.rb` (`emitter`, `database_url`), `spec/openlanes/events/bus_spec.rb`, `spec/openlanes/events/database/{recorder,tasks}_spec.rb`.
- **Depends on:** B7.
- **Shape:** see contract, "Write path". The `events` rows are append-only (`readonly?` once persisted), and a duplicate `event_id` is skipped.
- **Done when:** recording the same event twice leaves one row; a raising database subscriber still leaves the JSONL line; `agent_started` then `agent_finished` moves a task from `running` to `completed`, a blocked finish to `blocked`, and `run_finished` closes a leftover `running` as `failed`.

### B9 Loader, plans and agents sync, `events migrate` and `events load` (D1)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/events/database/loader.rb`, `lib/openlanes/cli/events/subcommands/{migrate,load}.rb`, `lib/openlanes/cli.rb` (those two registrations, written first), `spec/openlanes/events/database/loader_spec.rb`, `spec/openlanes/cli/events/{migrate,load}_spec.rb`.
- **Depends on:** B8.
- **Shape:** see contract, "CLI". Plans are upserted by `ordinal` with an emoji-free title, and agents by `name` with their Markdown body and `digest`.
- **Done when:** loading the two-node fixture twice inserts the events once; a `PlansFixture` tree yields `plans` rows whose titles carry no emoji; `--dry-run` writes nothing; with no database configured both commands exit 1 and name the key.

### B10 Reader, `Events.source` and `GET /api/reports` (D1)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/events/database/reader.rb`, `lib/openlanes/events.rb` (`source`), `lib/openlanes/web/app.rb` (the `/api/reports` route only), `openapi.yaml` (plan folder), `spec/openlanes/events/database/reader_spec.rb`, `spec/openlanes/web/reports_api_spec.rb`, `spec/integration/reports_api_spec.rb`.
- **Depends on:** B8.
- **Shape:** see contract, "HTTP surface". `Reader#events` returns `Event` values, so `Events.report` is the one aggregation behind the CLI and the page.
- **Done when:** `reports_api_spec.rb` covers 200 from the database, 200 from the log, 400, 404 and 503; the integration spec shows `GET /api/reports` and `events report --format json --source database` agree.

## Frontend

### F3 Nav button and the `/reports` route (D1)

- **Discipline:** front end.
- **Owns:** `web/src/shell/**` (the nav), the router entry for `/reports`, and their tests.
- **Depends on:** nothing; builds against `openapi.yaml`.
- **Shape:** a nav button swaps the page between Board and Reports. They are separate pages, and loading one unmounts the other, closing its event stream.
- **Done when:** a component test shows the button switches routes and the Board's `EventSource` is closed on `/reports`.

### F4 Reports page (D1)

- **Discipline:** front end.
- **Owns:** `web/src/reports/**`, `web/cypress/e2e/reports*.cy.ts`.
- **Depends on:** F3; B10 for the live check.
- **Shape:** renders every `Result` field from `GET /api/reports`, with shadcn chart components where the repo has them. `cost_usd: null` renders `unknown`, and `estimated` renders `(est.)`. The 404 and 503 bodies render their `message`.
- **Done when:** unit tests cover the `unknown` and `(est.)` cases and the 404 and 503 states; the Cypress spec described in the contract's integration proof passes.

### F5 `events report --source` and docs (D1)

- **Discipline:** front end (CLI and docs).
- **Owns:** `lib/openlanes/cli/events/subcommands/report.rb`, its spec, `docs/events.md` (the database section).
- **Depends on:** B10.
- **Shape:** `--source database|log`, defaulting to the database when one is configured. The docs cover `events.database`, `events migrate` and `events load`, and the Reports page.
- **Done when:** the CLI spec covers both sources, and the docs spec checks the database section.

### F1 `openlanes events report` command, and the integration check

- **Discipline:** front end (CLI).
- **Owns:** `lib/openlanes/cli/events/subcommands/report.rb`, `lib/openlanes/cli/events/events.rb` (if the prefix group needs a base), `lib/openlanes/cli.rb` (the `events` registration only), `lib/openlanes/presentation/events_report.rb`, `spec/openlanes/presentation/events_report_spec.rb`, `spec/openlanes/cli/events/report_spec.rb`, `spec/integration/events_report_spec.rb`.
- **Must not touch:** `lib/openlanes/events.rb` and `lib/openlanes/events/*` (B1, B2, B3, B5).
- **Depends on:** B4, B5.
- **Shape:** `openlanes events report [--dir PATH] [-o [FILE]] [--format table|json]`. Reads through `Events::Log` and `Events::Report`, renders `Report::Result` through `Presentation::EventsReport#render`, which returns a string and prints nothing. STDOUT carries the report, STDERR the progress and the box. Estimated cost carries an `(est.)` label; `nil` cost renders as `unknown`, never `$0`. When events are disabled it says so and names the `.openlanes.yml` key.
- **Integration check (this unit owns it):** `spec/integration/events_report_spec.rb` builds a `PlansFixture` tree with `events.enabled: true` in its `.openlanes.yml` and `XDG_STATE_HOME` pointed at a temp directory. It drives the real `Runner` for one round with an injected executor (one agent completes, one blocks), runs the real `Unblocker` on an answered `blocked.md`, and applies a merged `PrOutcomes` outcome from the `GitHub` double (the network seam, the only double besides the executor). It then runs `exe/openlanes events report --format json` as a subprocess, and must show: completion 1 of 2, 1 block over 1 unique run, one time-to-answer, one merged PR, usage grouped under the executor's adapter, and no key outside the allowlist in any line of the JSONL file.
- **Done when:** `presentation/events_report_spec.rb` covers the estimated label and `unknown` cost; `cli/events/report_spec.rb` covers `-o`, `--format json` and the disabled message; `spec/integration/events_report_spec.rb` passes as described.

### F2 Docs: configuration and multi-machine behaviour

- **Discipline:** front end (docs).
- **Owns:** `README.md` (the `## Configuration` section only), `docs/events.md`, `spec/openlanes/docs/events_doc_spec.rb`.
- **Must not touch:** `lib/openlanes/presentation/documentation.rb` (derived conventions, unrelated to events), any `lib/` file.
- **Depends on:** B3 (the config key and default path).
- **Shape:** `docs/events.md` documents the `events:` key, the default XDG path and its dependence on 021.00, the event kinds and their allowlisted fields, what is never stored (code, prompts, conversation text, `total_cost_usd`), and multi-machine behaviour: one writer per file, late arrival from offline nodes, nothing rewritten. `README.md` links to it from `## Configuration`.
- **Done when:** `events_doc_spec.rb` asserts `docs/events.md` exists and names the three multi-machine points, and that `README.md` links to it (spec item 11).

## HTTP surface

Yes, since D1: `GET /api/reports` (B10), described in `openapi.yaml` in this folder and in `contract.md`.

## How to test

Run each command from the repository root, after `eval "$(rbenv init -)"`.

- `bundle exec rspec spec/openlanes/events` → 0 failures. Covers B1 to B3, B5 and B6: event identity and the payload allowlist (an unlisted key raises), the usage mapping (an unknown cost is `nil`, never `0`), the sink and its location under `$XDG_STATE_HOME`, the log reader and aggregates, and the PR and human-answer events, recorded once.
- `bundle exec rspec spec/openlanes/engine/events_emit_spec.rb spec/openlanes/config_spec.rb` → 0 failures. Covers B4, `run_started`, `agent_started`, `agent_finished`, `block_raised`, `failure` and `run_finished` from a real `Runner` round, and B3's `events:` key: off by default, `enabled` must be `true` or `false`, and `dir` must be absolute.
- `bundle exec rspec spec/openlanes/cli/events spec/openlanes/presentation/events_report_spec.rb` → 0 failures. Covers F1, the `openlanes events report` command and its table and JSON output.
- `bundle exec rspec spec/integration/events_report_spec.rb` → 2 examples, 0 failures. The end-to-end proof: a real `Runner` round, a real `Unblocker` and `PrOutcomes` with the GitHub double, then `exe/openlanes events report --format json` as a subprocess. The report shows completion, blocks, time to answer, a merged PR and usage.
- `bundle exec rspec spec/openlanes/docs` → 0 failures. Covers F2: `docs/events.md` exists, names the three multi-machine points, and `README.md` links to it.
- `bundle exec rspec` → 0 failures. The only pending specs are the ones that need `web/dist`. Then `bundle exec rubocop` → no offenses.
- By hand, in a scratch git repo that has an empty `.plans/` and a `.openlanes.yml` holding `events: { enabled: true }`:
  - `XDG_STATE_HOME=$PWD/state <checkout>/exe/openlanes events report` prints a box saying there is no event log at `.../state/openlanes/<project>-<6 hex>/events` yet. Nothing gets written inside the repository.
  - Change `enabled` to `maybe` and run it again: it refuses with `events.enabled: "maybe" is not true or false`.
  - Run `openlanes run` on a plan with events enabled, then run `openlanes events report`. It prints the table: completion rate, blocks, time to answer, PR outcomes, and usage per adapter and model. A computed cost carries `(est.)`, and a codex or pi cost reads `unknown`. `--format json` gives the same figures for scripts.
- Read `docs/events.md`. It explains the config key, the default path, every event kind with its allowed fields, what is never stored, and how events behave across several machines.

- D1, once B7 to B10 land: `bundle exec rspec spec/openlanes/events/database spec/openlanes/web/reports_api_spec.rb spec/integration/reports_api_spec.rb` → 0 failures. Then, with `events: { enabled: true, database: sqlite }`, run `openlanes events migrate` and `openlanes events load` twice. The second load inserts 0 rows. `curl localhost:<port>/api/reports` returns the figures that `openlanes events report --format json` prints.
