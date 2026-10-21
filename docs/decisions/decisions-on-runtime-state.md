# Decisions on runtime state outside `.plans/`

Plan 021.00. `.plans/` holds what is committed; what is true only on one machine, for one run, lives in the runtime state directory.

## Inventory

| File | Kind | Where it lives now |
| --- | --- | --- |
| `spec.md`, `plan.md`, `state.json`, `blocked.md`, `discarded.md`, `delayed.md`, `pull-requests.md`, `INDEX.md`, `BACKLOG.md` | durable | the plan folder, committed |
| `openlanes-state.json` (`Engine::StateFile`) and its `.<pid>.tmp` sibling | operational | `<state dir>/openlanes-state.json` |
| plan lock (`Plans::Lock`) | operational | `<state dir>/locks/<ordinal>.lock` |
| `run: {pid, host}` on each `state.json` stage | operational inside a durable file | no longer written; the run's `StateFile` record holds pid and host |
| `state.json.<pid>.<tid>.tmp`, `blocked.md.<pid>.tmp` | transient | still in the plan folder, now ignored by `.plans/**/*.tmp` |
| traces, control files, progress logs, the `flock` plan key | operational | `Dir.tmpdir`, unchanged |
| port registry | operational | `${XDG_STATE_HOME:-~/.local/state}/openlanes/ports.json`, unchanged |

## Location

- `<state dir>` is `$XDG_STATE_HOME/openlanes/<basename(root)>-<6 hex of sha256(realpath root)>`, falling back to `~/.local/state` when `XDG_STATE_HOME` is unset, empty or relative (`OpenLanes::Runtime`).
- `root` is the directory holding `.plans/`. The harness and an agent handed the same `--dir` therefore address one state directory.
- XDG state over a repo-local `.openlanes/`: a repo-local directory would still have to be ignored, and would still ride along in every snapshot of the tree.

## Reading old layouts

- `Lock.read(dir)` reads the state directory first, then the legacy `locked-by.pid` in the folder. Nothing writes the legacy file.
- `StateFile#load` reads the new path, then `.plans/openlanes-state.json`, then `.plans/tmp/openlanes-state.json`. Nothing writes or deletes either legacy file: it is the only record a half-finished run has.
- `PlanState#stranded` still reads `run` from stages older releases wrote; the schema keeps `run` as an optional, deprecated property.
- The fallbacks are removed one release after this one ships.

## `.gitignore`

- `StateFile.ensure_ignored!` adds one line, `.plans/**/*.tmp`, and nothing else. It never edits or removes a line it did not write; the old `.plans/openlanes-state.json` and `locked-by.pid` lines stay where they are in existing repositories.

## Foreign locks

- `Lock#foreign?` is `host != Socket.gethostname`.
- A foreign lock is held for as long as it exists: never stale, never cleared by `resync dirs` or `Lock.remove`, and shown with its host and start time in `list-plans` and the control room (`locked.foreign` in the snapshot). There is no expiry (Q1).
- `previous_run_dead?` on a `StateFile` recorded on another host is false: its pid names a process this machine cannot see.

## Recorded assumptions

- **Q4.** `Socket.gethostname` is assumed stable on macOS across network changes. Unverified; if it is not, a stable host id replaces it.
- **Q5.** A legacy foreign-host `locked-by.pid` is read for one release, then ignored.
- **Q6.** Moving a checkout changes the root's hash and orphans its runtime record. Accepted; the legacy fallback does not cover it.
- **Q7.** Each worktree has its own root and so its own state directory. Whether one worktree should see another's locks is unanswered.
- **Q8.** The directory's name is the root's basename plus the hash.
