---
created: 2026-10-16
lane: full
---

# Runtime State Outside Plans

Source: GitHub issue #51, https://github.com/kigster/openlanes/issues/51 — "Move machine-specific run state out of the plan workspace"

## Problem

The plan tree mixes human-authored work artifacts with machine-specific operational state. The run state file is stored under `.plans/`, and plan locks live inside individual plan directories. This couples recovery and concurrency details to the workspace users browse, commit, archive, and migrate.

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

