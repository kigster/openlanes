---
created: 2026-10-16
starts: research
---

# Runtime State Outside Plans

Source: GitHub issue #51, https://github.com/kigster/openlanes/issues/51 — "Move machine-specific run state out of the plan workspace"

## Problem

The plan tree mixes human-authored work artifacts with machine-specific operational state. The run state file is stored under `.plans/`, and plan locks live inside individual plan directories. This couples recovery and concurrency details to the workspace users browse, commit, archive, and migrate.

Research narrowed the problem: `openlanes-state.json` and `locked-by.pid` are the two machine-local files that belong elsewhere (Research, Inventory). Two temp-file patterns inside plan folders are not git-ignored at all, and `state.json` carries machine fields (`run.pid`, `host`) inside a durable file.

## Proposal

Define a dedicated ignored runtime-data location (for example, `.openlanes/` or an XDG state directory) for process/run state, locks, and other machine-local data. Keep durable, reviewable plan artifacts in the workspace. Decide explicitly which per-plan records are durable product history and which are operational state.

## Acceptance criteria

- Inventory every runtime or machine-specific file currently written under `.plans/`, including `openlanes-state.json`, temporary state files, lock files, and any generated run records.
- Specify one documented location and lifecycle for each category.
- Ensure the location is ignored by Git without modifying unrelated user ignore rules silently.
- Preserve recovery of interrupted runs and safe lock cleanup across local and foreign hosts.
- Provide backward-compatible reads or a migration path for existing workspaces.

## What we are trying to achieve

Give machine-local run state its own ignored location, separate from the `.plans/` tree that people browse, commit and archive. Keep durable plan artifacts in `.plans/`, and decide per file whether it is product history or operational state.

## Why it matters

Today the run state file and per-plan locks sit inside `.plans/`, so recovery and concurrency details travel with the workspace. Moving them lets `.plans/` stay reviewable, and lets interrupted runs and stale locks be handled without touching plan folders.

## What already exists

- `lib/openlanes/engine/state_file.rb`: the restart state file, documented as gitignored because it describes one machine's run. Its `.gitignore` handling (around lines 48–66) adds ignore lines once and asks about the lock line separately. This is the closest existing pattern for "ignore runtime files without silently editing user rules".
- `lib/openlanes/engine/plan_locks.rb`: counts the `locked-by.pid` files in plan folders. Both halves of a pair share one lock file, and a folder renamed after the first hold carries its lock along.
- `lib/openlanes/plans/lock.rb`: the lock model itself. Not yet read in detail.
- `lib/openlanes/live/run_state.rb`: a second run-state implementation under the live control room. Not yet read in detail; check whether it overlaps `state_file.rb`.
- `lib/openlanes/plans/plan_state.rb` and `schemas/plan-state.schema.json`: per-plan `state.json`, which the README describes as durable history (rounds, tokens, signatures, messages).
- `README.md`, "Plan folders": documents `locked-by.pid` (process id, host, start time), git-ignored, and `resync dirs` removing a lock whose process is gone on this host. Host-awareness is therefore already in the design; foreign-host handling is not.
- Specs: `spec/openlanes/engine/state_file_spec.rb`, `spec/openlanes/live/run_record_spec.rb`, `spec/integration/restart_spec.rb`, `spec/openlanes/plans/plan_state_spec.rb`. These cover recovery and are the place to start for the migration tests.
- `docs/decisions/decisions-on-plan-folder-naming.md`: the existing decisions record for `.plans/` layout.

## What research needs to settle

- Inventory: list every file the code writes under `.plans/` at runtime (`openlanes-state.json`, temporary state files, `locked-by.pid`, run records), and mark each durable or operational. The `lib/openlanes/` grep is only a first pass.
- Location: `.openlanes/` in the project root, or an XDG state directory. Each option needs a rule for keying by project and by host.
- Git ignore: how to add the ignore entry without editing unrelated lines in `.gitignore`.
- Foreign hosts: how a lock taken on another machine is recognised as live or stale when the pid cannot be checked locally.
- Migration: whether to read old `.plans/` locations as a fallback, and when to move them.
- `lib/openlanes/plans/lock.rb` and `lib/openlanes/live/run_state.rb`: confirm their roles before deciding the layout.

## Research

Checked against the code in `openlanes.worktrees/021.00-runtime-state-outside-plans` (main branch at `0d0d99c`). No test suite was run; the claims below come from reading the code and from `git check-ignore`, which ran against this repo's `.gitignore`.

### Inventory: what the code writes under `.plans/`

Runtime files that live inside `.plans/`:

- `openlanes-state.json`, plus its `openlanes-state.json.<pid>.tmp` sibling. Operational. Written by `StateFile#save` (`lib/openlanes/engine/state_file.rb:118-125`). Ignored by the repo `.gitignore:22-23`.
- `locked-by.pid`, one per plan folder. Operational. Written and removed by `Plans::Lock` (`lib/openlanes/plans/lock.rb:47-65`, `:79`). Ignored by `.gitignore:39`.
- `.plans/tmp/openlanes-state.json`. Legacy. Read-only fallback, never written (`state_file.rb:25`, `:95-103`). Ignored by `.gitignore:21`.
- `state.json.<pid>.<tid>.tmp` inside each plan folder. Operational, transient. Written by `PlanState#write` (`lib/openlanes/plans/plan_state.rb:399-403`). **Not ignored**: `git check-ignore` returns no match for this name.
- `blocked.md.<pid>.tmp` inside each plan folder. Transient, renamed over `blocked.md` (`lib/openlanes/engine/conversions.rb:152-156`). **Not ignored**, same check.

Durable files, committed on purpose, not to be moved:

- `spec.md`, `plan.md`, `state.json` (`plan_state.rb:40`). `state.json` is durable history, but it also carries machine fields: the dispatcher writes `run: {pid, host}` into it (`lib/openlanes/engine/dispatcher.rb:973`). Those fields are operational data inside a durable file.
- `blocked.md` (`conversions.rb:119`, `live/commands.rb:241-244`), `discarded.md` (`engine/pr_outcomes.rb:88`), `delayed.md` (`lifecycle/aging.rb:130`), `pull-requests.md` (`lifecycle/creator.rb:126`), `INDEX.md` (`plans/index.rb:63`), `BACKLOG.md` (`lifecycle/brief.rb:44`).

Runtime files already outside the repo and the plan tree:

- Run traces and agent control files: `Dir.tmpdir/openlanes-traces` (`execution/executor.rb:367`, `execution/control.rb:56-63`).
- Plan lock, a `flock` on a per-plan key: `Dir.tmpdir/openlanes-plan-<16 hex>.lock` (`plans/plan_state.rb:408`, `:419-421`). The key is the SHA-256 of the absolute plans directory and the plan's ordinal, so it survives renames.
- Progress logs: `Dir.tmpdir/openlanes-<kind>-<name>-<6 hex>.log` (`engine/progress_log.rb:94-98`).
- Port registry: `${XDG_STATE_HOME:-~/.local/state}/openlanes/ports.json` (`apps/ports.rb:40-50`, `:150-151`). **This is the one place that already uses an XDG state directory.**
- Redis copy of the run record (`live/keys.rb`, `live/run_record.rb`).

### Location: `.openlanes/` or XDG state

Recommendation: an XDG state directory, `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<6 hex of sha256(root)>/`, keyed the way `progress_log.rb:94-98` already keys its names.

- The XDG spec defines `$XDG_STATE_HOME` for "state data that should persist between (application) restarts", defaulting to `$HOME/.local/state` when unset or empty. Paths must be absolute; a relative value is ignored. ([XDG Base Directory spec 0.8](https://specifications.freedesktop.org/basedir/0.8), retrieved 2026-10-16; [ArchWiki, XDG Base Directory support](https://wiki.archlinux.org/index.php/XDG_Base_Directory_support), retrieved 2026-10-16.)
- `Dir.tmpdir` does not meet the requirement `state_file.rb:15` sets for the run state: "a reboot must not lose it". Traces and locks in `Dir.tmpdir` are fine there, because nothing recovers from them after a reboot.
- `.openlanes/` in the checkout is the weaker choice. It needs a `.gitignore` line, which is the edit this plan wants to avoid. It is per checkout, so a worktree gets its own empty copy. Deleting the checkout deletes the recovery record.
- The `ports.json` precedent (`apps/ports.rb:40-50`) means the XDG path is already a convention in this code, not a new one.

### Git ignore without editing unrelated rules

- Today: `StateFile.ensure_ignored!` (`state_file.rb:58-71`) appends its lines to the end of `.gitignore`, touches nothing else, and reports the edit through `UI` (`engine/run_workflow.rb:194-195`). It only runs for a real `run`, not a dry run. It already meets "no silent edits". It does still edit a committed file.
- If the state moves to XDG, the state file needs no ignore line at all. `locked-by.pid` needs none either once it moves out of the folder.
- `.git/info/exclude` is the other option. It is per clone and never committed, so it needs no edit to `.gitignore` ([GitHub, Ignoring files](https://docs.github.com/en/get-started/git-basics/ignoring-files), retrieved 2026-10-16; [gitignore(5)](https://sites.uclouvain.be/SystInfo/manpages/man5/gitignore.5.html), retrieved 2026-10-16). The cost is that a teammate's clone gets no entry. That only matters while a runtime file stays inside `.plans/`.
- The temp files are the gap found here. `state.json.*.tmp` and `blocked.md.*.tmp` are not ignored (verified above). Either add `*.tmp` under `.plans/` or keep the temp file out of the tree. The temp must stay on the same filesystem as its target for `File.rename` to be atomic, so the first option is the one that holds.

### Foreign hosts

- A lock records `host` and `pid` (`lock.rb:21`, `:48`). `alive?` returns false for any lock from another machine (`lock.rb:88-89`), so `stale?` is false and `held_elsewhere?` is true (`lock.rb:110`). A foreign lock is never cleared automatically. `resync dirs` removes only stale locks (`lifecycle/resync.rb:157-168`), and `dispatcher.rb:437` skips the plan while the lock stands.
- A pid cannot be checked off its own host. So "live or stale" for a foreign lock can only rest on time, and the code has the timestamp it needs: `started_at` (`lock.rb:21`). It does not have a heartbeat. A time threshold cannot tell a slow run from a dead one without one. The choice of threshold is a product decision and is listed under "could not settle".
- `StateFile#previous_run_dead?` (`state_file.rb:203-211`) checks the pid locally and never checks `host`. `begin_run!` records `pid` and `root` but no host (`state_file.rb:137`). A state file copied from another machine could report a live pid that is an unrelated process. The lock model is host-aware; the state file is not.
- Unverified: `Socket.gethostname` can change on macOS when the network changes. If that happens, a machine's own locks read as foreign and never clear. I did not reproduce it; a test would need to stub `Socket.gethostname` to show it.

### Migration

- The state file already has a read fallback. `StateFile#load` reads the current path, then `.plans/tmp/openlanes-state.json` when the current path holds nothing (`state_file.rb:103-112`). Nothing writes or deletes the legacy file. Specs: `spec/openlanes/engine/state_file_spec.rb`, `spec/integration/restart_spec.rb`.
- For the new location, reuse that pattern: read the XDG path, fall back to `.plans/openlanes-state.json`, never delete the old file. This is the "backward-compatible read" the acceptance criteria ask for.
- Locks: readers of `Plans::Lock.read` are `lifecycle/resync.rb:157,168`, `engine/dispatcher.rb:437`, `presentation/reporter.rb:118`, `live/snapshot.rb:138`, and `engine/plan_locks.rb:24,40`. The 🔑 mark (`reporter.rb:118`) and the control room's `locked` field (`snapshot.rb:138`) would both need to read the new path. A lock left in a folder by an older version is stale on its own host and is cleared by `resync dirs` once its pid is gone; a foreign one needs a fallback read for one release, or a person removes it.
- Specs to extend: `spec/openlanes/plans/lock_spec.rb`, `spec/openlanes/engine/plan_locks_spec.rb`, `spec/openlanes/engine/state_file_spec.rb`, `spec/openlanes/live/run_record_spec.rb`.

### Roles of `lock.rb` and `run_state.rb`

- `lib/openlanes/plans/lock.rb` is the per-plan claim. One `locked-by.pid` per plan folder, claimed with `O_EXCL` (`lock.rb:51`). It says whether an agent is working on the plan now. It is the lock, not a run record.
- `lib/openlanes/live/run_state.rb` is not a second file writer. It holds what a person said about the run: held questions, held cars, queued models (`run_state.rb:15-22`). It is kept by `RunRecord`, in Redis and under the `live` key of `openlanes-state.json` (`run_record.rb:103-108`, `state_file.rb:171-177`). Its name overlaps with `StateFile`, but it is a payload inside it.
- `engine/plan_locks.rb` does not count files, as "What already exists" says. It holds an in-memory count of running jobs per ordinal (`plan_locks.rb:10-47`). It writes the lock when the count goes 0→1 and removes it 1→0.

### Contradictions

- **Spec vs code, `plan_locks.rb`.** The spec says it counts `locked-by.pid` files. The code counts jobs in memory. Production runs the in-memory count (`engine/dispatcher.rb:145`).
- **Spec acceptance vs code, cross-host cleanup.** The acceptance criteria require "safe lock cleanup across local and foreign hosts". The code declines to clean foreign locks at all (`lock.rb:84-85`). Production runs the code.
- **Durable vs machine-local, `state.json`.** The durable record carries `run.pid` and `host` (`dispatcher.rb:973`). Production writes them there. Moving the lock out of the folder will not move these fields unless they are split out too.
- **Host awareness, lock vs state file.** The lock checks the host (`lock.rb:82`, `:89`). The state file does not (`state_file.rb:203-211`). Production runs both.
- **Git ignore, repo vs code.** This repo's `.gitignore` lists `.plans/tmp/`, `.plans/openlanes-state.json`, and `locked-by.pid`, but not the two temp-file patterns above. Production `ensure_ignored!` (`state_file.rb:33`) writes the same first two lines and not the temp pattern. Production runs both.

### Could not settle

1. **Foreign-lock expiry.** What threshold, or heartbeat design, says a lock from another host is dead? This is a product choice between a stuck plan and a double run. Recommendation: keep foreign locks held and show them as "held on <host> since <time>", with a person clearing them. Add a heartbeat before any automatic expiry.
2. **Whether `state.json` keeps `run.pid` and `host`.** Moving those fields out is a schema change to `schemas/plan-state.schema.json`. Recommendation: move them into the XDG run record, and leave `state.json` with history only.
3. **Whether the lock moves out of the folder at all.** It is keyed by folder today, and the 🔑 mark and `resync dirs` depend on that. Recommendation: move it to `<xdg-dir>/locks/<ordinal>.lock`, keyed by ordinal as `PlanState#lock_key` already is, so renames do not matter.
4. **Whether `ensure_ignored!` is retired.** Once the state file and lock have moved, it has nothing to add. Retiring it is a behaviour change for repos that rely on the appended lines. Recommendation: stop writing it, keep reading the legacy lines.

### Findings, Conclusion & References

Findings:

- Five runtime files sit in `.plans/`: the state file and its temp, `locked-by.pid`, and two temp files that git does not ignore.
- Every durable file is written as plan history and should stay where it is.
- The XDG state directory already exists as a convention (`apps/ports.rb`). It meets the reboot requirement that `Dir.tmpdir` does not.
- Foreign locks cannot be cleared on evidence. The only way out is time, and that needs a heartbeat first.
- The state file already has a read fallback to a legacy path. Reuse that pattern for migration.

Conclusion: put the state file and the per-plan lock under `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<hash>/`, keep `.plans/` for durable files only, and read the old `.plans/` locations as fallbacks for one release. Fix the two unignored temp patterns in the meantime. Foreign locks stay held until a person or a heartbeat clears them.

References (all retrieved 2026-10-16):

- [XDG Base Directory Specification 0.8](https://specifications.freedesktop.org/basedir/0.8): `XDG_STATE_HOME` and its default.
- [ArchWiki, XDG Base Directory support](https://wiki.archlinux.org/index.php/XDG_Base_Directory_support): notes that these variables are normally unset and applications fall back to the default.
- [GitHub, Ignoring files](https://docs.github.com/en/get-started/git-basics/ignoring-files): `.git/info/exclude` is per clone and not committed.
- [gitignore(5), mirror](https://sites.uclouvain.be/SystInfo/manpages/man5/gitignore.5.html): the same, from the man page.

No paywalled or licensed sources were used.

## Framings

1. **Hygiene.** `.plans/` must hold only reviewable files. Move every runtime file out, and fix the leaks (unignored `*.tmp`).
2. **Recovery and concurrency.** The lock and the run state are a machine's private bookkeeping. Redesign them for restart safety and for locks held by other hosts, and let the location follow.
3. **Portability.** `.plans/` should be copyable, archivable and migratable with no stale machine data in it.

Chosen: framing 2 with 1 as its means. The acceptance criteria turn on recovery and cross-host locks, and a move that ignored foreign hosts would only relocate the problem. Framing 3 follows for free.

## Goal

After this ships, `.plans/` holds only durable, reviewable plan artifacts. The run state file, per-plan locks and the machine fields of `state.json` live in a per-project XDG state directory, `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<6 hex of sha256(root)>/`. An interrupted run still resumes after a reboot, and a lock taken on another host is shown as held, with its host and start time, rather than silently ignored. Existing workspaces keep working through read fallbacks to the old paths.

## Non-Goals

1. No heartbeat and no automatic expiry of foreign-host locks (see Q1).
2. No change to durable files: `spec.md`, `plan.md`, `blocked.md`, `discarded.md`, `delayed.md`, `pull-requests.md`, `INDEX.md`, `BACKLOG.md`, and the history parts of `state.json`.
3. No move of traces, progress logs or the `flock` lock out of `Dir.tmpdir`, nor of `ports.json`; they already sit outside the tree (Research, Inventory).
4. No change to `live/run_state.rb`, which is a payload inside the state file, not a second writer (Research, Roles).
5. No deletion of legacy files in existing workspaces.
6. No new CLI command for editing runtime state beyond what migration needs.

## In scope

Each item is checked by the named spec.

1. A single `Runtime` path resolver returns the project state directory from `$XDG_STATE_HOME` (absolute values only, else `~/.local/state`) and the root. Check: new spec covers unset, empty, relative and absolute `XDG_STATE_HOME`, and two roots giving distinct directories.
2. `StateFile` reads and writes `<state-dir>/openlanes-state.json`; its temp file goes in the same directory. Check: `state_file_spec.rb` asserts no `openlanes-state.json*` appears under `.plans/` after `save`.
3. `StateFile#load` falls back to `.plans/openlanes-state.json`, then `.plans/tmp/openlanes-state.json`, and never deletes either. Check: `state_file_spec.rb` and `spec/integration/restart_spec.rb` resume from each legacy path.
4. `StateFile#begin_run!` records `host` and `previous_run_dead?` treats a record from another host as not provably dead. Check: spec with a stubbed `Socket.gethostname`.
5. `Plans::Lock` writes `<state-dir>/locks/<ordinal>.lock` (pid, host, started_at), keyed by ordinal so a folder rename does not matter. Check: `lock_spec.rb` renames the folder while locked.
6. All lock readers (`resync.rb`, `dispatcher.rb`, `reporter.rb`, `live/snapshot.rb`, `plan_locks.rb`) go through the new path, and also read a legacy `locked-by.pid` in the folder. Check: reporter and snapshot specs show the 🔑 mark and `locked` for a lock at each location.
7. A foreign-host lock stays held and is reported with host and start time in the reporter and `live/snapshot.rb`. Check: spec with a lock whose host differs.
8. A stale legacy `locked-by.pid` on this host is still cleared by `resync dirs`. Check: `resync` spec.
9. `state.json` no longer receives `run.pid`/`host`; they go to the runtime record. `schemas/plan-state.schema.json` and `plan_state.rb` are updated, and old files with those fields still load. Check: `plan_state_spec.rb` loads a file with the fields and a schema validation of a new file without them.
10. Temp files `state.json.*.tmp` and `blocked.md.*.tmp` are covered by an ignore rule. Check: `git check-ignore` on both names in the repo's `.gitignore` and in `ensure_ignored!`'s output.
11. `StateFile.ensure_ignored!` stops adding lines for paths that no longer live in `.plans/`, and never edits lines it did not write. Check: `state_file_spec.rb` against a `.gitignore` with unrelated content.
12. The README "Plan folders" section and `docs/decisions/` record the inventory, the durable-versus-operational split, the location and the migration. Check: the decisions file exists and the README no longer says `locked-by.pid` lives in the plan folder.

## Out of scope

- Foreign-lock heartbeat or expiry: product tradeoff between a stuck plan and a double run.
- Redis copy of the run record: unrelated to the files under `.plans/`.
- Removing the legacy fallbacks: waits one release, then a separate plan.
- Windows state paths: the code and the XDG spec target Unix; nothing in the research covers Windows.

## Back end / front end

| Item | Half |
| --- | --- |
| 1, 2, 3, 4, 5, 8, 9, 10, 11 | Back end (`luke-backend`): `engine/`, `plans/`, `lifecycle/`, schema |
| 6 | Both: readers in `engine/` and `lifecycle/` are back end; `presentation/reporter.rb` and `live/snapshot.rb` are the displays (`rey-frontend`) |
| 7 | Front end (`rey-frontend`) renders "held on <host> since <time>"; back end supplies the host and start time |
| 12 | Back end writes the docs; `rey-frontend` has nothing to build |

The pair's contract: `Plans::Lock.read` returns a value with `host`, `pid`, `started_at` and `foreign?`, and the displays only format it.

## Open questions

1. **Q1.** Foreign-lock expiry. Assumed: none, locks stay held until a person clears them. Needs a product decision before any heartbeat plan.
2. **Q2.** Moving `run.pid`/`host` out of `state.json` is a schema change. Assumed yes, with old files still loading. Reader tools outside this repo are unknown.
3. **Q3.** Stopping `ensure_ignored!` from adding lines changes behaviour for repos that relied on it. Assumed acceptable, since the paths it protected no longer exist in `.plans/`.
4. **Q4.** Does `Socket.gethostname` change on macOS when the network changes, leaving a machine's own locks looking foreign? Unverified (Research, Foreign hosts). If it does, a stable host id is needed.
5. **Q5.** A legacy foreign-host `locked-by.pid`: assumed read for one release, then ignored. The release count is not decided.
6. **Q6.** The hash of the project root changes if the checkout moves, orphaning the runtime record. Assumed acceptable; the legacy fallback does not cover it.
7. **Q7.** Worktrees have different roots, so they get separate state directories. Assumed intended; whether a run in one worktree should see locks from another is unanswered.
8. **Q8.** The `<project>` name: assumed the root's basename.

## Risks to planning or execution

- Q1 may be pushed back by the owner as part of "safe lock cleanup across hosts"; the acceptance criteria could then be read as requiring expiry. Mitigation: state in the PR that "safe" is read as "never wrongly cleared".
- Lock readers are spread over six files (Research, Migration); a missed reader would show a plan as unlocked and allow a double run. Plan a single reader entry point first.
- Specs build real trees in temp directories; they must set `XDG_STATE_HOME` to a temp directory or they will write into the developer's home.
- `spec_helper.rb`'s `REPO_ROOT` quirk (CLAUDE.md) means coverage figures are noisy; do not use them as the check.
- Any plan folder created by an older version and carrying `run:` fields must keep loading, or restart specs break.

## Conclusion

When this ships, `.plans/` contains only plan artifacts a person would review. Run state and locks live in a per-project XDG state directory that survives reboots, locks are keyed by plan ordinal and carry host and start time, foreign-host locks are shown and never auto-cleared, and temp files are ignored. Older workspaces keep running through read-only fallbacks, and the decision is recorded in `docs/decisions/` and the README.
