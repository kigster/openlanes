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
- `Changes.between` drops `.plans/**` from the fixture side too, so a case that seeds other plans for the agent to read does not count them as deleted.
- Eval cases `evals/cases/ewoki-linker/{link-one,none,shared-files-only}.yml`, each with `pass/` and `fail/` recordings.

## Amendments

- amended: `spec/openlanes/engine/dispatcher_spec.rb`, `runner_spec.rb` and `live/live_context.rb` run with `Registry.new.without("ewoki-linker")`; their keyless fixtures are about routing, not linking, and the gate has its own spec (`dispatcher_linker_spec.rb`).
- amended: the dry-run preview named at `cli/run/run.rb:~475` lives in `engine/run_workflow.rb#takers`; that is what was changed.
- amended: `lib/openlanes/evals/changes.rb` changed in round 2 (U5's file): the ewoki fixtures seed `.plans/034.00…/spec.md` in `repo:`, and only the after side ignored `.plans`, so every recording showed one phantom deletion.
- amended: `spec/openlanes/evals/corpus_spec.rb` counts an agent as working a plan when it handles or precedes a state; it previously excluded ewoki (`handles: []`).
- amended: U7 hands the plan on through the chain in the same round, not the next one: the dispatcher chains the lane's agent right after ewoki returns. A 📋 fixture needs a blank `plan.md`, since one with a body reads as planned and resync lifts it to ⭐.
- observed, not changed: in a dry run nothing writes the key, so the preview shows ewoki for both of its in-agent rounds and then the planner for the same plan.

## Integration proof

`spec/openlanes/cli/run_linker_spec.rb`: `./exe/openlanes run --dry-run --isolation shared` on a fixture with 050 keyless at 📋 and another with `depends_on: []` reports `would invoke ewoki-linker` for 050 only.

## Status, round 1

- [x] U1, U2, U3 (incl. resumption path), U4 (incl. `dispatcher_linker_spec.rb`, all three lanes), U5
- [x] U6 eval cases `link-one`, `none`, `shared-files-only` with recordings
- [x] U7 `runner_linker_spec.rb`, `cli/run_linker_spec.rb`

After round 1: `bundle exec rspec` 3160 examples, 0 failures, 9 pending; `bundle exec rubocop` no offenses.

## Requirement not met, 2026-10-17 re-verification

Requirement: `bundle exec rspec` exits 0. It does not on this machine today: 3187 examples, 30 failures, all in `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb`, each `Ports::Exhausted: every port from 11100 to 11999 is taken`.

Cause is the machine, not the plan: every TCP connect to 127.0.0.1 succeeds, on any port including 1, with nothing listening (`lsof` empty), inside and outside the sandbox. `Ports.free?` treats an answering port as taken. This plan's diff touches nothing under `apps/`. The same suite was 0 failures on 2026-10-16. Rubocop clean; every other check passes. Details in `blocked.md`.
