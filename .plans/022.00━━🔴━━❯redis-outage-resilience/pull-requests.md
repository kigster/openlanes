# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 110 | [\[022.00\](A) Redis Outage Resilience](https://github.com/kigster/openlanes/pull/110) | Open 🟡 |

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
- `bundle exec rspec spec/openlanes/live/redis_outage_integration_spec.rb spec/openlanes/engine/redis_outage_spec.rb`: 5 examples, 0 failures. amended (round 4): wrong count; the two files hold 3 and 1, 4 together (hansolo finding 3).
- `just web-build && just web-e2e`: build exit 0; Cypress 5 specs, 23 tests, all passed.

## Front end (rey-frontend, round 2)

hansolo's findings 1-5 all sit in back-end code, plan.md/contract.md prose and README; none names a front-end file. No change to the front end.
- `cd web && npx vitest run`: 39 files, 450 tests passed.
- The `backoff` in `web/src/api/events.ts` is the SSE reconnect delay, unrelated to the Redis probe schedule.

## Answers, round 1

hansolo's rejection is one PR conversation comment, not inline review threads (`gh api repos/kigster/openlanes/pulls/110/comments` is empty), so each finding is answered here.

- Finding 1 (#59 proof), fix: `plan.md` "Reproduction" and "B1" now say the `NOGROUP` fix is main's `14a7f439`, not this PR; `redis_outage_spec.rb` is described as a real-Redis regression test, 1 example, that passes on `main`. `contract.md` "Integration proof" says the same.
- Finding 2 (Backoff, Config, `unavailable!` claims), fix: removed from `plan.md` B2, B3, B5, B7 and `contract.md` "Back-end interfaces (built)", which now splits what main had (`ec5b95eb`, `14a7f439`) from what this branch built. The spec's configurable initial/cap/jitter is recorded as not built; main's Fibonacci schedule stands.
- Finding 3 (example counts), fix: counts corrected to 3 (integration) and 1 (`redis_outage_spec`); the round 3 "5 examples" line above is marked amended.
- Finding 4 (README duplication), fix: `README.md`, the "When Redis goes away" section is folded into the "A lost Redis" paragraph.
- Finding 5 (stale PR head a15b34e8), no change from me: publishing is the harness's; it must push local `HEAD` (`371d70b1` plus this round's edits).

## Back end (luke-backend, round 4)

- `bundle exec rspec`: 4094 examples, 0 failures. Coverage 98.86%.
- `bundle exec rubocop`: 552 files, no offenses.
- `bundle exec rspec spec/openlanes/live/redis_outage_integration_spec.rb spec/openlanes/engine/redis_outage_spec.rb spec/openlanes/live/outage_spec.rb spec/openlanes/live/outage_report_spec.rb spec/openlanes/engine/dispatcher_outage_spec.rb`: 22 examples, 0 failures.
