# Contract: 008.01 Ewoki Linker

Back end only (`## Frontend` has no units), so rey-frontend is not started and this file holds no rey interface.

## Baseline

Before any unit: `bundle exec rspec` reported 3123 examples, 0 failures, 9 pending; `bundle exec rubocop` clean.

## Interfaces built

- `Agent#precedes` (array of status keys, default `[]`) and `Agent#precedes?(status)`.
- `Registry#preceding(status) -> Array<Agent>`, the only reader of `precedes:`; `for_status` and `team_for` never return a preceding-only agent.
- `Routing.preceding_for(registry, subject, state, limit: nil) -> Agent | nil`: nil unless `Spec#depends_on` is nil; counts failed attempts from `state.json` `stages` (statuses other than Started and Completed).
- `Dispatcher::LINK_ATTEMPTS = 3`; `Dispatcher#preceding` assigns the linker before the state's own candidates; after the limit, `#park_unlinked` writes a ⭕️ `blocked.md` with one `## B1` (a: write `depends_on:` by hand, Recommended; b: retry).
- `RunWorkflow#takers` and `#assignable` ask `Routing.preceding_for` / `Agent#precedes?` (the dry-run takers preview).
- `Executor#allowed_for(agent, subject)`: a preceding agent gets `Edit(/<plan>/spec.md)` only, and `Write`, `MultiEdit`, `NotebookEdit` denied; the resumption (compaction) path carries the same scope.
- Eval check `spec_only` (`expect.spec_only: true`).

## Amendments

- amended: `spec/openlanes/engine/dispatcher_spec.rb`, `runner_spec.rb` and `live/live_context.rb` run with `Registry.new.without("ewoki-linker")`; their keyless fixtures are about routing, not linking, and the gate has its own spec (`dispatcher_linker_spec.rb`).
- amended: the dry-run preview named at `cli/run/run.rb:~475` lives in `engine/run_workflow.rb#takers`; that is what was changed.

## Integration proof

`spec/openlanes/cli/run_linker_spec.rb` (U7, not yet written): `./exe/openlanes run --dry-run --isolation shared` on a fixture with 050 keyless at 📋 and another with `depends_on: []` reports `would invoke ewoki-linker` for 050 only.

## Status, round 1

- [x] U1, U2, U3 (incl. resumption path), U4 (incl. `dispatcher_linker_spec.rb`, all three lanes), U5
- [ ] U6 eval cases `link-one`, `none`, `shared-files-only` with recordings
- [ ] U7 `runner_linker_spec.rb`, `cli/run_linker_spec.rb`

After round 1: `bundle exec rspec` 3160 examples, 0 failures, 9 pending; `bundle exec rubocop` no offenses.
