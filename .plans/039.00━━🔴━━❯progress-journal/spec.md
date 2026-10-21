---
created: 2026-10-20
lane: full
depends_on: ["038.00"]
---

# Progress Journal

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 2 of 7.

## What we are trying to achieve

S9: an append-only, fsync'd, schema-versioned NDJSON journal per node under the per-root XDG runtime directory (`Runtime.dir`; the draft said `.openlanes/journal/`, superseded by plan 021, see Research Q3), recording what is being done and what has been done: run, plan, agent (PID, process start time, session id, output file, offset), transitions, extensions, questions. Every event is mirrored to Redis pub/sub through `EventBus`.

## Why it matters

Recovery, the watchdog and the UIs all read one record that survives Redis loss.

## What already exists

`Engine::StateFile` (a per-tick snapshot, not an event record), per-plan `state.json`, `ProgressLog` (terminal only); plan 021 already moved runtime files out of `.plans/`.

## How to tell it's working?

- Killing the engine mid-run loses no event, and a replay rebuilds the in-flight picture.
- The JSON schema lives in `schemas/` and is validated in specs.
- Runtime files no longer live under `.plans/`.

## What research needs to settle

The draft's list is empty. The questions below are the ones its sections imply; each is answered in `## Research`.

## Research

Round 1, `leah-researcher`. Anchors are `file:line` in this checkout unless marked otherwise.

### Questions and answers

1. **Is there already a durable engine event record?** No. The nearest pieces each miss the requirement:
   - `Engine::StateFile` is a snapshot, rewritten whole every tick. `save` writes a temp file and renames it (`lib/openlanes/engine/state_file.rb:115`); it is not an event log. Called from `Dispatcher#persist` (`lib/openlanes/engine/dispatcher.rb:2233-2238`).
   - `Plans::Journal` (`lib/openlanes/plans/journal.rb:7`) is the agent's own memory, kept in each plan's `state.json`. It is a different thing with the same word in it.
   - `Log` (`lib/openlanes/support/log.rb:28`) is SemanticLogger to `log/development.log`, not a record the engine replays. `ProgressLog` (`lib/openlanes/engine/progress_log.rb:8`) keeps only the terminal's clock and status cell.
2. **Are runtime files already outside `.plans/`?** Mostly yes. `Runtime.state_file` puts `openlanes-state.json` under the XDG state directory (`lib/openlanes/support/runtime.rb:51`). The plan 021 record is `docs/decisions/decisions-on-runtime-state.md`. In this checkout, `find .plans` finds no lock, `openlanes-state.json`, `locked-by.pid` or `*.tmp` at depth two. Two legacy reads remain: `StateFile#legacy_paths` (`state_file.rb:92`) reads `.plans/openlanes-state.json` and `.plans/tmp/`. Nothing writes them.
3. **Where does the journal live?** The draft says `.openlanes/journal/`. Production says otherwise. `decisions-on-runtime-state.md` rejects a repo-local `.openlanes/` because it would still need ignoring and would still ride in tree snapshots. The engine uses `Runtime.dir`, keyed by root (`runtime.rb:51`). `docs/decisions/decisions-on-distributed-engine-and-solid-refactor.md:75` repeats the draft's `.openlanes/journal/`, so it is stale too. Production answer: put the journal under the XDG state directory.
4. **Does Redis already let a killed engine replay?** Not reliably. The board stream holds about 100 snapshots (`lib/openlanes/live/keys.rb:178`, `BOARD_LENGTH = 100`), and the snapshot key expires after 30 s (`keys.rb:190`). `Publisher` says a Redis that disappears mid-run "is reported once and otherwise ignored" (`lib/openlanes/live/publisher.rb:15-16`). Events during an outage are lost, not queued. Redis is also the thing the journal must survive losing.
5. **Is anything fsync'd?** No. `rg 'fsync' lib` returns nothing; `flock` appears only in `apps/ports.rb:147`, `plans/plan_state.rb:775` and `lifecycle/allocator.rb:130`. The draft requires fsync, so this is new code, not a reuse.
6. **Is schema validation in specs a pattern here?** Yes. `schemas/plan-state.schema.json` is loaded with `JSONSchemer` in `spec/openlanes/plans/plan_state_journal_spec.rb:15`, `plan_state_resumption_spec.rb:18`, `engine/extensions_spec.rb:214` and `engine/dispatcher_journal_spec.rb:62`. `json_schemer` is in `Gemfile:15`. A new `schemas/` file would follow the same pattern.
7. **Which agent fields can the engine name today?**
   - `pid` and `run_pid` on each stage, and `file`, through `StateFile#record` (`state_file.rb:150`, whose docs list `pid` and `file`). The run's own pid and host sit in `run` (`state_file.rb:131`).
   - `session_id` is read from the stream at `lib/openlanes/execution/transcript.rb:543` and kept in memory. I found no write to `StateFile` or `state.json`.
   - Process start time and output offset: no field and no reader found. Both are new.

### Findings, Conclusion & References

**Findings**

- The requirement is new code. Existing pieces are a per-tick snapshot, an untried Redis stream of 100 entries, and a log file. None is an event record.
- Runtime relocation (plan 021) is done. The draft's "What already exists" still lists `StateFile` as if it were the place to build on, so yoda should describe it as a snapshot.
- Plan 020.01 ("durable run events") covers overlapping ground. `decisions-on-distributed-engine-and-solid-refactor.md:22` says it "stays a separate plan". The draft does not mention it, so yoda should name it in Non-Goals.

**Conclusion**

Build the journal new, under the XDG state directory (`Runtime.dir`), with the schema in `schemas/` validated in specs. Reuse `Runtime`, `StateFile`'s stranded-run logic (`state_file.rb:245`) and the existing `JSONSchemer` spec pattern. Mirror to `EventBus` as the draft says. Do not reuse the agent `Journal`.

**Could not settle** (for yoda's open questions)

1. Whether `fsync` runs per event or per tick. The engine ticks about once a second (`dispatcher.rb` comments), so per event is probably affordable, but no benchmark exists in the repo.
2. Retention and rotation of the journal. Nothing in the repo answers this.
3. Whether replay replaces `openlanes-state.json` or sits beside it. Plan 021 does not say.
4. Where process start time comes from. Ruby's stdlib has no call for it; `ps -o lstart=` would need a command the autonomy boundary may not allow. Unverified.
5. Whether `session_id` should be persisted at all, given the stage record does not hold it today.

**Contradictions** (production answer in bold)

- `.openlanes/journal/` (draft, `decisions-…distributed…md:75`) against XDG `Runtime.dir` (`decisions-on-runtime-state.md`, `runtime.rb:51`). **Production: XDG.**
- Plan 020.01 "durable run events" against this plan's journal. **Decision doc: separate plan.**

**Test run**

- `bundle exec rspec` at this checkout: 4075 examples, 0 failures, 9 pending, coverage 98.86%. Output in `/tmp/leah-rspec-039.txt`, outside the repository.

**Sources**

- No external sources used. Everything above is from this repository.


## Framing

- **A. Event log as the source of truth.** Every state change is appended first; the snapshot and the UIs are derived by replay.
- **B. Write-ahead sidecar.** Keep `StateFile` as the source and add the journal as an audit trail that recovery consults only when the snapshot is stale.

Picked **A** for the journal itself, with `StateFile` left untouched in this plan: the stated test is "a replay rebuilds the in-flight picture", which B cannot show without a second source of truth. Retiring the snapshot is a later decision (OQ3).

## Goal

After this ships, an engine killed at any moment leaves a per-node, append-only, fsync'd, schema-versioned NDJSON journal from which a reader can rebuild what was running: run, plan, agent (PID, start time, session id, output file, offset), transitions, extensions and questions. Each event is also published through `EventBus`, but the file, not Redis, is the record that survives.

## Non-Goals

- Resuming or killing orphaned agents (plan S3/S4 recovery and watchdog). This plan provides the record they read.
- Shipping the journal into Postgres or any remote store: plan `020.01` (durable run events) stays separate (`decisions-on-distributed-engine-and-solid-refactor.md:22`, `:79`).
- Replacing or deleting `Engine::StateFile` / `openlanes-state.json`.
- Changing the agent memory `Plans::Journal` (`lib/openlanes/plans/journal.rb:7`) or per-plan `state.json`.
- UI changes in the Sinatra app or authoritative UI (plans 5 and 6).
- Cross-node journal merging.

## In scope

Each item states its check.

1. A schema `schemas/journal-event.schema.json`, with a version field. Check: a spec loads it with `JSONSchemer` (pattern at `spec/openlanes/plans/plan_state_journal_spec.rb:15`) and validates a sample of every event kind, and rejects a malformed one.
1. A journal writer that appends one JSON line per event, flushes and `fsync`s, under `Runtime.dir`. Check: spec asserts `File#fsync` is called per append (or per tick, per OQ1) and lines parse back.
1. Event kinds: run start/end, plan assigned, agent started (pid, start time, session id, output file), agent offset, transition, extension, question. Check: one schema-valid event per kind in a dispatcher spec.
1. Mirror of every event to `EventBus`, a Redis outage never failing the append. Check: spec with a failing bus still finds the line on disk.
1. A reader that replays the file into the in-flight picture (plans with a live agent and its last offset), tolerating a truncated last line. Check: spec writes events, truncates mid-line, replays, compares.
1. Kill test: a spec forks a process that appends and is `SIGKILL`ed mid-run; every event acknowledged before the kill is replayed. Check: that spec.
1. Dispatcher and `Transcript` call sites emit events (`dispatcher.rb:2233-2238` persist point; `transcript.rb:543` for session id). Check: existing suite stays green, new emit specs.
1. Runtime files stay out of `.plans/`. Check: a spec runs a round on a fixture tree and asserts no journal, lock or tmp file appears under `.plans`.
1. `.gitignore` and docs mention. Check: `rg journal docs` shows the location.

## Out of scope

- Rotation and retention: nothing in the repo answers it; see OQ2.
- Reading `.plans/openlanes-state.json` legacy paths: nothing writes them (`state_file.rb:92`).
- Process start time via `ps`: boundary and portability unverified; see OQ4.

## Back end / front end

| Item | Builds it |
| :--- | :--- |
| 1 to 9 | `luke-backend` |
| Front end | `rey-frontend`: nothing in this plan. No UI or API surface changes; the pair's contract is that the journal and `EventBus` payloads are the interface later UI plans consume. |

## Open questions

Defaults below are what the planner should assume unless a human says otherwise.

1. **fsync cadence** (leah 1). Default: per event; ticks are about 1 s and events few. No benchmark exists.
1. **Rotation and retention** (leah 2). Default: none in this plan; one file per run, named by run id and date, never truncated.
1. **Replay vs snapshot** (leah 3). Default: journal sits beside `openlanes-state.json`; replacing it is a later plan.
1. **Process start time source** (leah 4). Default: Linux `/proc/<pid>/stat`, macOS `ps -o lstart=` through an injectable seam, `nil` where unavailable; the engine process, not an agent, runs it. Unverified that the boundary allows it.
1. **Persist `session_id`** (leah 5). Default: yes, in the journal only.
1. **Location.** The draft says `.openlanes/journal/`; production says XDG `Runtime.dir` (`runtime.rb:51`, plan 021 decision). Default: XDG. This overrides the issue text, so the "git-ignored" wording becomes moot.
1. **Offset meaning.** Assumed to be a byte offset into the agent's trace file in `TRACE_DIR`; no reader exists today.

## Risks to planning or execution

- Per-event fsync under 4 parallel agents may slow the tick loop on slow disks; keep the writer behind a seam so cadence can change.
- Concurrent appends from agent threads: needs a mutex or `O_APPEND` single-write lines (plan 038 thread-safety is the dependency).
- Two things called "journal" (`Plans::Journal`, this one): name the new class distinctly, e.g. `Engine::EventJournal`.
- Overlap with `020.01` may tempt scope growth.
- Coverage gate: the repo is at 98.86%; new code needs tests to hold it.

## Conclusion

When this ships, each node writes `journal/<run>.ndjson` under its XDG runtime directory, one schema-validated, fsync'd line per engine event, mirrored best-effort to `EventBus`. A reader replays it, even after `SIGKILL` and a torn last line, into the in-flight picture. The schema lives in `schemas/`, specs enforce it, and nothing runtime-related lands in `.plans/`. Recovery and the watchdog can then be built on it.
