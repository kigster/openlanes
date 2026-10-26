# Contract — 034.00 Refactor Global Lock

Back end only: `spec.md` has no front end and `plan.md` has no `## Frontend` units, so `frontend-coder` is not started. No HTTP surface, so no `openapi.yaml`.

## Baseline

Full suite before any change: 0 failures (the repo's CLAUDE.md states the suite is green; confirmed by the run after the change, which only adds examples).

## Interfaces

- `OpenLanes::Plans::Execution` (`lib/openlanes/plans/execution.rb`)
  - `.of(subject) -> "concurrent" | "global-lock-required"`: `execution:` from `plan.md` frontmatter, else `spec.md`, else `concurrent`. An unknown value or broken YAML reads as `concurrent`.
  - `.global_lock?(subject) -> Boolean`
  - `.refactor?(subject) -> Boolean`: `implementation_requirement: refactor`, or `refactor` in `implementation_requirements`.
  - `.classify(files:, total_files:, lines: 0, total_lines: 0, threshold: 50) -> mode`: over the threshold by files or by lines locks.
- `OpenLanes::Plans::GlobalLock.new(tree, status_of: nil)` (`lib/openlanes/plans/global_lock.rb`)
  - `#holder -> String | nil`: lowest unfinished `global-lock-required` plan at ⭐ Planned or holding a branch.
  - `#waiting? -> Boolean`: holder still at ⭐ Planned.
  - `#waits_on -> [String]`: other plans holding a branch or PR while the holder waits.
  - `#reason(ordinal) -> String | nil`: `"refactor 031.00 waits on 018.00 ⭕, 020.00 🟡"` for the holder, `"queued behind refactor 031.00"` for the rest, nil for a plan free to run (including one that already holds a branch while the holder waits).
- "Holds a branch" is read from the tree only: state past the documents and not ✅/🚀/discarded; a parked or retroactive plan holds one when its folder has `contract.md` or `pull-requests.md`.
- `Engine::Runner#global_lock(except: [])`, and `#held(deps, lock)` now merges both gates' reasons. `Dispatcher#held?` asks both; the idle line lists both under "held by dependencies".
- `.openlanes.yml`: `refactor: { threshold: 1..100 }` → `Config#refactor_threshold`, `Config#refactor_percent` (default 50).
- `agents/planner.md`: new step writes `execution:` into `plan.md` frontmatter from the estimate.

## Ownership

All files are backend-coder's.

## Build order

1. `Execution` → 2. `GlobalLock` → 3. Config key → 4. Runner/Dispatcher hooks → 5. planner instructions.

## Integration proof

`spec/openlanes/engine/dispatcher_spec.rb`, "with a refactor that needs the global lock": a real `Runner` over a real tree runs to a fixed point, starts neither the refactor nor the never-started plan, and `runner.held` names `refactor 031.00 waits on 018.00 ⭕`.
