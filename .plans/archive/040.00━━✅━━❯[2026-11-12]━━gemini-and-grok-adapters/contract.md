# Contract: 040.00 Gemini and Grok Adapters

## Baseline (round 4, 2026-11-12)

`bundle exec rspec` on `main` at 4fcb6eb2, before any change: 5936 examples, 10 failures, 9 pending.

- `spec/openlanes/agents/routing_spec.rb` (3), `spec/openlanes/engine/dispatcher_spec.rb` (1), `spec/openlanes/engine/run_workflow_spec.rb` (3): the suite read the checkout's own `.openlanes.yml`, whose `frontend: true` (added in 4fcb6eb2) sent frontend-coder to every routing example and stopped runs missing `desired_codebase_quality`.
- `spec/openlanes/engine/redis_outage_spec.rb` (1), `spec/openlanes/live/redis_outage_integration_spec.rb` (2): `Live::Session` shared one `RedisClient` connection between the engine and the adapter probe thread (PR 2, D7). Replies were swapped between threads (`hgetall` received a String; `can't modify string; temporarily locked`).

## Interfaces

All five PRs' interfaces are already on `main` (see plan.md, every unit checked). The front end reads them unchanged:

- Snapshot `adapters`: one `Availability#wire` per adapter (`name`, `available`, `reason`, `models`, `checked_at`).
- `create_plans` accepts `phases: { <phase> => { adapter, model } }`, validated by `Plans::Spec`.

## File ownership

- backend-coder, this round: `spec/spec_helper.rb`, `lib/openlanes/live/session.rb`, `.openlanes.yml` (`coverage:` restored)., `docs/architecture/openlanes-live.md` (regenerated).
- No front-end file changed.

## Integration proof

`spec/openlanes/live/redis_outage_integration_spec.rb` against a real Redis, nothing stubbed: green after the fix.
