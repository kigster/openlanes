# Front-end units, plan 008.00

"Front end" in this gem is the human-facing CLI output.

## F1 `list-plans` shows who blocks whom

- **Discipline:** front end.
- **Owns:** `lib/openlanes/presentation/reporter.rb`, `lib/openlanes/cli/list_plans/list_plans.rb` (only if the command needs to pass anything new), `spec/openlanes/presentation/reporter_spec.rb`, `spec/openlanes/cli/list_plans_spec.rb`.
- **Must not touch:** `lib/openlanes/plans/*` (B1, B2), `lib/openlanes/engine/*` (B3), `spec/openlanes/integration/*` (B4).
- **Depends on:** B2. Reads `tree.dependencies` only; computes nothing about dependencies itself.
- **Builds:**
  - The row of a plan with a non-empty `blocks_of` carries `blocks 050.00` (several ordinals comma-separated, in ordinal order) in its tail.
  - A plan with an unknown dependency shows it as a problem, the same way `Spec` problems are shown today.
  - A plan that depends on a ✅ plan shows a warning that the entry is ignored.
  - A plan on a cycle shows `cycle: 034.00 → 050.00 → 034.00`.
  - `Reporter#render` still returns a string and prints nothing.
- **Done when:** `spec/openlanes/presentation/reporter_spec.rb` covers each of the four rows above, and `spec/openlanes/cli/list_plans_spec.rb` asserts the 034 row reads `blocks 050.00` under `NO_COLOR=1`, with one example that stubs `UI.color?` to cover the coloured path.
