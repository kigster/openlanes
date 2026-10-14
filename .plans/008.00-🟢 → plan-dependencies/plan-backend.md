# Back-end units, plan 008.00

## B1 `Spec#depends_on` and validation (items 1, 2)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/plans/spec.rb`, `spec/openlanes/plans/spec_spec.rb`.
- **Must not touch:** `lib/openlanes/plans/tree.rb`, `lib/openlanes/plans/dependencies.rb` (B2), anything under `engine/` (B3), `presentation/` (F1).
- **Depends on:** nothing.
- **Builds:** a `depends_on` attribute on `Plans::Spec`, read in `Spec.from`:
  - `nil` when the key is absent, `[]` when empty, `Array<String>` of canonical `"NNN.MM"` otherwise.
  - A non-string entry (`[034]`, which YAML reads as octal 28) or a string `Ordinal` cannot parse becomes a `Spec` problem, and the entry is dropped rather than coerced.
  - `"034"` is accepted and normalised to `"034.00"` through `Ordinal`, so the gate compares one form.
  - `Spec#default?` keeps its meaning: a spec with only `depends_on:` set is not default.
- **Done when:** `spec/openlanes/plans/spec_spec.rb` has examples for absent (`nil`), empty (`[]`), filled (`["034.00"]`), `[034]` reporting a problem, and `["034.00"]` reporting none.

## B2 `Plans::Dependencies` (item 3, cycles, unknown and closed entries)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/plans/dependencies.rb` (new), `lib/openlanes/plans/tree.rb`, `spec/openlanes/plans/dependencies_spec.rb` (new).
- **Must not touch:** `spec.rb` (B1), `engine/` (B3), `presentation/` (F1). Never writes to any plan's `spec.md`.
- **Depends on:** B1.
- **Builds:** `Plans::Dependencies.new(tree)`, exposed as `Tree#dependencies` (memoised, dropped by `Tree#reload`), with `Tree#blocks_of(ordinal)` delegating to it. All answers are `Array<String>` of ordinals, sorted:
  - `depends_on(ordinal)`: the plan's declared list, or `nil` when the key is absent.
  - `blocks_of(ordinal)`: every plan whose `depends_on` names this one. Computed, never stored (N6).
  - `waiting_on(ordinal)`: the declared entries that are not ✅ (unknown ordinals included; ⭕️, 🅱️ and 💤 count as not done).
  - `unknown(ordinal)`: entries with no folder in the tree.
  - `closed(ordinal)`: entries naming a ✅ plan, which the gate ignores.
  - `cycle_of(ordinal)`: the cycle this plan is on, as a path that starts and ends with the same ordinal, or `nil`. `cycles` lists them all.
- **Done when:** `spec/openlanes/plans/dependencies_spec.rb`, on a real tree through `PlansFixture`, asserts `blocks_of("034.00") == ["050.00"]` with 050 depending on 034, that `034.00/spec.md` is byte-identical afterwards, and covers `waiting_on` for an open, a ✅ and a 🅱️ dependency, `unknown`, and a two-plan and a three-plan cycle.

## B3 Gate, ordering and deadlock reason (items 4, 5)

- **Discipline:** back end.
- **Owns:** `lib/openlanes/engine/dispatcher.rb`, `lib/openlanes/engine/runner.rb`, `spec/openlanes/engine/dispatcher_spec.rb`, `spec/openlanes/engine/runner_spec.rb`.
- **Must not touch:** `lib/openlanes/plans/*` (B1, B2), `presentation/reporter.rb` (F1), `spec/openlanes/integration/*` (B4).
- **Depends on:** B2. Must run sequentially as a single unit: both items edit `dispatcher.rb`.
- **Builds:**
  - A gate in its own dispatcher method (spec risk "Dispatcher size"), consulted by `next_dispatchable` before candidates are built: a plan whose `tree.dependencies.waiting_on` is non-empty, or which has a `cycle_of`, is skipped this tick. Plans whose key is absent are not gated.
  - Order: within a round, plans with a non-empty `blocks_of` come before plans nobody waits for; ties keep today's order. Applied where `next_dispatchable` walks `@runner.in_scope`, not by reordering the tree.
  - Deadlock reason: a held plan is reported beside today's `waiting` list with its reason, `waiting on 034.00` or `cycle: 034.00 → 050.00 → 034.00`, so a run that stops at a fixed point with work left says why.
- **Done when:**
  - `spec/openlanes/engine/runner_spec.rb`: two plans, 050 depending on open 034; only 034 starts. A second example with 034 ✅ starts 050. A third with a cycle starts neither and reports the cycle.
  - `spec/openlanes/engine/dispatcher_spec.rb`: candidate ordering puts a plan with `blocks` ahead of one without, and keeps existing order otherwise. One example per lane (`full`, `plan`, `quick`) that the gate holds a waiting plan.

## B4 Integration check

- **Discipline:** back end.
- **Owns:** `spec/openlanes/integration/plan_dependencies_spec.rb` (new). Nothing else.
- **Must not touch:** every file owned by B1, B2, B3 and F1. A failure here is fixed in the owning unit.
- **Depends on:** B3, F1.
- **Builds:** one spec that drives the real executable path, nothing stubbed but the `GitHub` seam the suite always injects: a `PlansFixture` tree in a temp directory, then `list-plans` and `run --dry-run` through the CLI.
- **Done when:** `spec/openlanes/integration/plan_dependencies_spec.rb` shows, under `NO_COLOR=1`:
  - the 034 row of `list-plans` reads `blocks 050.00`, and `034.00/spec.md` is byte-identical before and after;
  - `run --dry-run` assigns an agent to 034 and none to 050, and names 050 as waiting on `034.00`;
  - with 034 and 050 depending on each other, `run --dry-run` assigns neither and reports the cycle for both.
