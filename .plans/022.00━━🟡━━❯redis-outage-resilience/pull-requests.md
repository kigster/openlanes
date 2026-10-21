# Pull Requests

## F1 front end (rey-frontend, round 1)

- `cd web && npx vitest run`: 34 files, 358 tests passed.
- `cd web && npx eslint .` and `npx tsc -b`: no findings.
- Tests for F1: `web/src/shell/Header.test.tsx`, "Redis outage notice" (fresh and null: silent; stale: alert; recovered: status line).

## Back end (luke-backend, round 2)

- `bundle exec rspec spec/openlanes/live/redis_outage_integration_spec.rb spec/openlanes/engine/redis_outage_spec.rb` (the integration proof against a real `redis-server`, plus the #59 reproduction): 5 examples, 0 failures.
- `just web-build && just web-e2e`: build exit 0; Cypress 5 specs, 23 tests, all passed.
- `bundle exec rubocop`: 446 files, no offenses.
- `bundle exec rspec`: 3175 examples, 30 failures, 9 pending. The 30 are the baseline in `contract.md`, all in `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb`, and fail identically on clean `7186635`. The 9 pending are `web/dist is missing`. Blocked on the exit-0 requirement: `blocked.md`, B1.

## Back end (luke-backend, round 3)

- Took `origin/main`'s port-probe fix (`ff03ca48`): `lib/openlanes/apps/probe.rb` and `ports.rb` copied verbatim, plus main's `connectable?` helper in `spec/openlanes/apps/supervisor_spec.rb` and `spec/openlanes/cli/app_spec.rb`. Details are in `contract.md`, "Baseline cleared".
- `bundle exec rspec`: 3175 examples, 0 failures. Coverage 98.71%.
- `bundle exec rubocop`: 446 files, no offenses.
- `bundle exec rspec spec/openlanes/live/redis_outage_integration_spec.rb spec/openlanes/engine/redis_outage_spec.rb`: 5 examples, 0 failures.
- `just web-build && just web-e2e`: build exit 0; Cypress 5 specs, 23 tests, all passed.
