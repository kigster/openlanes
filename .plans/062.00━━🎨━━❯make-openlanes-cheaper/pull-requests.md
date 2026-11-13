# Pull Requests

## Back end, round 1 (backend-coder)

- `bundle exec rubocop`: 856 files inspected, no offenses detected.
- `bundle exec rspec spec/openlanes/integration/plan_budget_spec.rb`: 1 example, 0 failures (the integration proof).
- `cd web && npx vitest run`: 531 passed.
- Full suite: see below.
- `bundle exec rspec` (full): 5977 examples, 1 failure (thread-safety inventory row for the new Store guard), fixed after; `bundle exec rspec spec/openlanes/thread_safety_inventory_spec.rb spec/openlanes/docs`: 9 examples, 0 failures.
- Baseline before this plan: 8 failures on clean HEAD (routing_spec x3, run_workflow_spec x3, dispatcher_spec:523, redis_outage_integration_spec:72). Cause and fix:
  - the specs read the checkout's own `.openlanes.yml` (rewritten in 4fcb6eb2: `frontend: true`, `desired_codebase_quality: high`); `spec_helper.rb` now gives `Config.current` an empty config when the root is the gem checkout.
  - `Live::Store` shared one `RedisClient` across threads unguarded ("can't modify string; temporarily locked"); every command now runs under a `Monitor`. Row added to `docs/thread-safety.md`.
- Integration proof: `bundle exec rspec spec/openlanes/integration/plan_budget_spec.rb`: 1 example, 0 failures.
- Coverage: `.openlanes.yml` gained `coverage:` (minimum 95, `report_command: jq ".result.line" coverage/.last_run.json`). The command and report print; the whole-suite figure was not re-read after the last run, so check it against 95 before merge.

## Integration proof, round 1 (frontend-coder, last to finish)

- `bundle exec rspec` (includes `spec/openlanes/integration/plan_budget_spec.rb`): 5977 examples, 0 failures, 9 pending; coverage 99.17%
- `bundle exec rubocop`: 856 files inspected, no offenses
- `cd web && npx vitest run`: 48 files, 531 tests passed
