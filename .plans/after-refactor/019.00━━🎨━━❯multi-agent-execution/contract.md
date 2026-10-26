# Contract 019.00 — Multi-Agent Execution

Owner: `backend-coder`. Partner: `frontend-coder`.

## Baseline

Full suite before any change, 2026-10-16, this worktree: `bundle exec rspec` → 3081 examples, 0 failures, 9 pending. Baseline failures: none.

## Interfaces frontend-coder calls

### Board snapshot, `cars[]` entry (`Live::Snapshot#car`)

- Key `subagents`: `string[]`, the names of the sub-agents in flight now for that car's agent, oldest first; the count is its length. `[]` when none. Never `null`, never absent from this engine. amended: upstream PR #55 landed the same field as names before this branch rebased; main's shape wins (see `plan.md`, Rebase decisions).
- Every other key unchanged.
- No new error: the field is derived from the board row, so a snapshot that renders at all carries it.
- Old engines (read-only boards on other machines) omit it; the UI reads a missing field as none (`car.subagents?.length`).
- Described in [`openapi.yaml`](openapi.yaml) beside this file.
- `web/src/api/fixtures/snapshot.json` carries `subagents` as a name list on every car (main's copy after the rebase): `snapshot_spec.rb` compares `Snapshot#car`'s keys to it.

### Demo engine (`openlanes web --demo`)

- Exactly one running car fans out. Its `subagents` cycles deterministically on the demo tick: 3 names for 4 ticks, 1 name for 4 ticks, `[]` for 4 ticks, then repeats (period 12 ticks). Every other demo car keeps the fixture's list throughout. amended: name lists instead of 3, 1, 0, to match the wire type.
- The fanned-out car is `001.00/frontend-coder`, named in `lib/openlanes/web/demo_board.rb` (`FANNED`, `FAN = [%w[Explore general-purpose Plan], %w[Explore], []]`, one entry per 4 ticks); F3 finds it by its `data-car` attribute. It starts at the fixture's two names until the first tick. A car that is no longer running reports `[]`.

### Where the number comes from

- `Transcript#running` / `Progress#running`: `Array<String>`, names of the sub-agents in flight, keyed by the `Task` call's `tool_use_id`. A `task_started` adds its key (named by `subagent_type`, else `description`), a `tool_result` or a `task_notification` whose `status` is `completed`, `failed` or `stopped` removes it, and `finish` clears it. An unknown status leaves the task in flight; a notification that overtook its start does not reopen it. amended: main's list replaces the branch's integer.
- Verified on a live recording (`spec/fixtures/streams/subagent-fanout.ndjson`, pinned `claude`, 2026-10-16): two `task_started`, two `task_notification` with `status: "completed"`.
- `Executor::Sessions#carry` adds earlier sessions' spawns to `subagents` and passes `running` through: a resumed session starts with none in flight.
- `Dispatcher` sets `job.running = progress.running`, so `Board::Row#running` is in flight now and `Board::Row#subagents` stays cumulative. `Snapshot#car` sends `subagents: Array(row.running)`. `Tally` reads `Executor::Result#subagents` (cumulative), unchanged. amended: the branch's `job.subagents = progress.running` would have put a list into an Integer field.

## File ownership

| Files | Owner |
| :--- | :--- |
| `lib/openlanes/execution/transcript.rb`, `executor.rb` and their specs | backend-coder |
| `lib/openlanes/engine/dispatcher.rb`, `board.rb`, `dispatcher_spec.rb` | backend-coder |
| `lib/openlanes/live/snapshot.rb`, `lib/openlanes/web/demo_board.rb` and their specs | backend-coder |
| `spec/fixtures/streams/subagent-fanout.ndjson` | backend-coder |
| `contract.md`, `openapi.yaml` | backend-coder |
| `web/src/api/fixtures/snapshot.json` (the `subagents` key only) | backend-coder |
| `web/src/api/fixtures/board.json` (demo fixture) | frontend-coder |
| `web/src/api/types.ts`, `web/src/board/sample.ts` | frontend-coder |
| `web/src/board/Car.tsx`, `board.css`, `Car.test.tsx` | frontend-coder |
| `web/cypress/e2e/subagents.cy.ts` | frontend-coder |

Shared files: none.

## Build order

B1 → B2 → (B3, B4). B5 independent. F1 → F2. F3 last, after B4, B5, F2.

## Integration proof

F3: `just web-build`, then `bin/web-e2e` running `web/cypress/e2e/subagents.cy.ts` against two real `openlanes web --demo` servers, nothing stubbed: the fanned-out car shows 3 `.car-stack-line` elements and `aria-label` "3 sub-agents running", later 0 lines and no label; every other car shows 0 lines.

## Amendments

- 2026-10-17, after the rebase onto `origin/main`: `subagents` is `string[]` (names) rather than an Integer count, because upstream PR #55 shipped it that way first. Entries above marked `amended:`. Mailed to frontend-coder.
