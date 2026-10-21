# Decisions on the progress journal

Plan `039.00` (S9 of issue #95). Dated 2026-10-21.

## What it is

`OpenLanes::Engine::EventJournal` appends one JSON line per engine event to `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<hash>/journal/<run id>.ndjson` (`Runtime.journal_dir`). Every line carries `v`, `seq`, `at`, `node`, `run_id` and `kind`, and validates against `schemas/journal-event.schema.json`. `EventJournal::Replay.call(path)` rebuilds the in-flight picture: the run, each plan's last transition, and every agent started and not ended, with its pid, start time, session id, trace file and last offset.

Kinds: `run_started`, `run_ended`, `plan_assigned`, `agent_started`, `agent_session`, `agent_offset`, `agent_ended`, `transition`, `extension`, `question`.

## Decisions

1. **Framing: the journal is the event record.** `Engine::StateFile` stays a per-tick snapshot and is untouched; retiring it is a later plan.
1. **fsync per event.** Ticks are about a second and events few. The writer holds a mutex around number, write, flush and `fsync`, and opens the file `O_APPEND`, so a kill tears at most the last line.
1. **No rotation or retention.** One file per run, named `<YYYYMMDD-HHMMSS>-<6 hex>`, never truncated.
1. **Beside `openlanes-state.json`, not replacing it.**
1. **Process start time** comes from `Execution::ProcessStart.of(pid)`: `/proc/<pid>/stat` on Linux, `ps -o lstart=` elsewhere, `nil` where neither answers. The engine runs it, never an agent, so the autonomy boundary does not apply.
1. **`session_id` is persisted in the journal only**, in `agent_started` when already known, otherwise in `agent_session` once the stream names it.
1. **Location: the XDG runtime directory**, not the draft's repo-local directory, which `decisions-on-runtime-state.md` rejected because it would need ignoring and ride in tree snapshots.
1. **Offset** is the byte size of the agent's raw trace (`Executor::Handle#trace`, in `Executor::TRACE_DIR`), journaled only when it grew.
1. **Redis is a mirror.** Each line is published on `Live::Keys#journal` after the fsync; a publish that raises is reported once and the line stays on disk.
1. **A newer `v` is skipped, not guessed at.** `Replay` counts torn lines and newer-version lines separately.
1. **Named `EventJournal`**, so it cannot be confused with `Plans::Journal`, the agents' memory in `state.json`.

## Not in this plan

Resuming or killing orphaned agents (S3/S4), shipping the journal to Postgres (`020.01`), cross-node merging, and UI changes.
