# Contract 019.00 — Multi-Agent Execution

Owner: `luke-backend`. Partner: `rey-frontend`.

## Baseline

Full suite before any change, 2026-10-16, this worktree: `bundle exec rspec` → 3081 examples, 0 failures, 9 pending. Baseline failures: none.

## Interfaces rey calls

### Board snapshot, `cars[]` entry (`Live::Snapshot#car`)

- New key `subagents`: Integer, `>= 0`, the number of sub-agents in flight now for that car's agent. `0` when none. Never `null`, never absent from this engine.
- Every other key unchanged.
- No new error: the field is derived from the board row, so a snapshot that renders at all carries it.
- Old engines (read-only boards on other machines) omit it; the UI reads a missing field as `0`.
- Described in [`openapi.yaml`](openapi.yaml) beside this file.
- `web/src/api/fixtures/snapshot.json` carries `"subagents": 0` on every car: `snapshot_spec.rb` compares `Snapshot#car`'s keys to it, so the key has to be there. Written by luke (only that key), mailed to rey as #1.

### Demo engine (`openlanes web --demo`)

- Exactly one running car fans out. Its `subagents` cycles deterministically on the demo tick: `3` for 4 ticks, `1` for 4 ticks, `0` for 4 ticks, then repeats (period 12 ticks). Every other demo car is `0` throughout.
- The fanned-out car is `001.00/rey-frontend`, named in `lib/openlanes/web/demo_board.rb` (`FANNED`, `FAN = [3, 1, 0]`, one entry per 4 ticks); F3 finds it by its `data-car` attribute. It starts at the fixture's value (2) until the first tick. A car that is no longer running reports 0.

### Where the number comes from

- `Transcript#running` / `Progress#running`: tasks keyed by `task_id` with a `task_started` and no `task_notification` whose `status` is `completed`, `failed` or `stopped`. The `result` event and the stream ending reset it to 0. An unknown status leaves the task in flight.
- Verified on a live recording (`spec/fixtures/streams/subagent-fanout.ndjson`, pinned `claude`, 2026-10-16): two `task_started`, two `task_notification` with `status: "completed"`.
- `Executor::Sessions#carry` adds earlier sessions' spawns to `subagents` and passes `running` through: a resumed session starts at 0 in flight.
- `Dispatcher` sets `job.subagents = progress.running`, so `Board::Row#subagents` means in flight now. `Tally` reads `Executor::Result#subagents` (cumulative), unchanged.

## File ownership

| Files | Owner |
| :--- | :--- |
| `lib/openlanes/execution/transcript.rb`, `executor.rb` and their specs | luke |
| `lib/openlanes/engine/dispatcher.rb`, `board.rb`, `dispatcher_spec.rb` | luke |
| `lib/openlanes/live/snapshot.rb`, `lib/openlanes/web/demo_board.rb` and their specs | luke |
| `spec/fixtures/streams/subagent-fanout.ndjson` | luke |
| `contract.md`, `openapi.yaml` | luke |
| `web/src/api/fixtures/snapshot.json` (the `subagents` key only) | luke |
| `web/src/api/fixtures/board.json` (demo fixture) | rey |
| `web/src/api/types.ts`, `web/src/board/sample.ts` | rey |
| `web/src/board/Car.tsx`, `board.css`, `Car.test.tsx` | rey |
| `web/cypress/e2e/subagents.cy.ts` | rey |

Shared files: none.

## Build order

B1 → B2 → (B3, B4). B5 independent. F1 → F2. F3 last, after B4, B5, F2.

## Integration proof

F3: `just web-build && just web-e2e` running `web/cypress/e2e/subagents.cy.ts` against `openlanes web --demo`, nothing stubbed: the fanned-out car shows 3 `.car-stack-line` elements and `aria-label` "3 sub-agents running", later 0 lines and no label; every other car shows 0 lines.

## Amendments

(none yet)
