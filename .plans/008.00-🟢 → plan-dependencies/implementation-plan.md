# Implementation plan, 008.00 (contract between luke-backend and rey-frontend)

## Baseline

`RBENV_VERSION=4.0.6 bundle exec rspec` before any change: see the line under "Baseline result" (filled in when the run ends). Research recorded `2214 examples, 0 failures`.

Baseline result (2026-10-13 19:21, seed 6184): `2214 examples, 0 failures`. No baseline failures.

## Interfaces rey calls

All ordinals are canonical `"NNN.MM"` strings. Every list is sorted and never nil, except `depends_on`.

| Call | Returns | Notes |
| --- | --- | --- |
| `Plans::Spec#depends_on` | `nil` (key absent), `[]`, or `Array<String>` | Bad entries (`[034]`, `"abc"`) are dropped and named in `Spec#problems` as `depends_on: <inspect> is not a quoted plan number like "034.00"`. |
| `tree.dependencies` | `Plans::Dependencies` | Memoised on the tree, dropped by `Tree#reload`. |
| `tree.blocks_of(ordinal)` | `Array<String>` | Same as `tree.dependencies.blocks_of`. |
| `deps.depends_on(ordinal)` | `Array<String>` or `nil` | The plan's declared list. |
| `deps.blocks_of(ordinal)` | `Array<String>` | Plans whose `depends_on` names this one. |
| `deps.waiting_on(ordinal)` | `Array<String>` | Declared entries not in ✅ Approved or 😎 Deployed. Unknown ordinals included. |
| `deps.unknown(ordinal)` | `Array<String>` | Entries with no folder in the tree. |
| `deps.closed(ordinal)` | `Array<String>` | Entries naming a ✅/😎 plan; the gate ignores them. |
| `deps.cycle_of(ordinal)` | `Array<String>` or `nil` | A shortest cycle through the plan, e.g. `["034.00", "050.00", "034.00"]`, starting at the asked ordinal. Only edges to plans not yet ✅/😎 count. |
| `deps.cycles` | `Array<Array<String>>` | One shortest cycle per strongly connected group, starting at its lowest ordinal. |
| `deps.reason(ordinal)` | `String` or `nil` | `"cycle: 034.00 → 050.00 → 034.00"`, `"waiting on 034.00, 041.00"` or `"unknown plan 099.00; waiting on 034.00"`; nil when free. Cycle wins; an entry naming no plan is said as `unknown plan`, not as a wait. |

`ordinal` may be an `Ordinal` or a `String`. Unknown ordinals answer `[]`/`nil`; nothing raises.

Errors: none raised. Problems surface as data (`Spec#problems`, `unknown`, `closed`).

## Engine (luke only)

- `Dispatcher#held?(subject)` (private): true when `deps.reason` is non-nil. `next_dispatchable` skips held plans.
- Order: `Dispatcher#blockers_first` (private): `next_dispatchable` walks `in_scope` with plans that have a non-empty `blocks_of` first, stable otherwise.
- `Runner#held(deps = dependencies)` → `Hash{String => String}` (`"050.00" => "waiting on 034.00"`): in-scope plans the gate holds, excluding plans already in a `StateMachine::SETTLED` state.
- `Runner#dependencies(except: [])`: `tree.dependencies` on a real run; on a dry run, a graph judging each plan by `Runner#effective_status` (what reconciliation would rename it to), except busy and foreign plans, which keep their folder state. The dispatcher gates and reports with the same graph.
- Report: amended: the reason is not logged per tick; `openlanes run` prints a `N plan(s) held by dependencies:` warning box listing `  050.00 waiting on 034.00` after its summary, and an idle staying run says `idle: held by dependencies: 050.00 waiting on 034.00`. Why: the run report is what a person reads at a fixed point; `lib/openlanes/cli/run/run.rb` (owned by nobody in the plan) gained `held_report`.

## File ownership

| File | Owner |
| --- | --- |
| `lib/openlanes/plans/spec.rb`, `spec/openlanes/plans/spec_spec.rb` | luke (B1) |
| `lib/openlanes/plans/dependencies.rb`, `lib/openlanes/plans/tree.rb`, `spec/openlanes/plans/dependencies_spec.rb` | luke (B2) |
| `lib/openlanes/engine/*`, `spec/openlanes/engine/{runner,dispatcher}_spec.rb` | luke (B3) |
| `lib/openlanes/presentation/reporter.rb`, `lib/openlanes/cli/list_plans/*`, their specs | rey (F1) |
| `spec/openlanes/integration/plan_dependencies_spec.rb` | luke (B4) |
| `lib/openlanes/cli/run/run.rb` | luke (amended: `held_report`, not in the plan's tables) |

No shared files.

## Build order

B1 → B2 → (B3 ‖ F1) → B4.

## Integration proof

`spec/openlanes/integration/plan_dependencies_spec.rb`: a real `PlansFixture` tree in a `git init`ed temp project, then `exe/openlanes list-plans` and `exe/openlanes run --dry-run --isolation shared` spawned as subprocesses under `NO_COLOR=1`. Nothing is stubbed, not even the GitHub seam: neither command reaches GitHub on a dry run.

## Assumptions

- Amended after review of #23: cycle detection follows only open edges (a dependency on a ✅ plan cannot deadlock), and uses Tarjan's strongly connected components plus a breadth-first ring per plan. The first version enumerated every path and took 2.6 s on 28 plans each waiting on the two before.

- A dependency on a 🗑 discarded plan counts as not done: the dependent waits and the report says so. A human drops the entry.
