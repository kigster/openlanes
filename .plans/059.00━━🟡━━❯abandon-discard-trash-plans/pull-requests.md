# Pull Requests

## Building, round 1 (backend-coder)

Tasks 1 to 6 of `plan.md` were already on `main` when this round started (`3e74922e Add abandoned and trashed plan states` and the work that followed): states, `Lifecycle::Rewiring`, `Lifecycle::Removal`, `Plans::RemovedReadme`, `resync dirs` placement, the `plans abandon|discard|trash` commands with `ReasonInterview`, and the PR watcher changes, each with its specs. This round verified them against `plan.md` and closed the gaps:

- `skills/openlanes/SKILL.md`: the stale sentence that still put discarded plans in `abandoned/` now names `abandoned/`, `discarded/` and `trashed/`.
- `.openlanes.yml`: a `coverage:` section (`bundle exec rspec`, minimum 95, `report_command` reading `.total.lines.percent` from `coverage/coverage.json`; the full run reported 99.14%).
- `plan.md`: `## Frontend` (no units) and `## Backend` sections.

No frontend: the plan is CLI and library work only, so there is no integration proof across halves.
- `spec/openlanes/agents/routing_spec.rb`: the baseline full run had 1 failure (`routing_spec.rb:32`, 3 in that file alone). Those examples read this repository's own `.openlanes.yml`, which says `frontend: true`, through `Config.current`. The spec now runs from the fixture's root.

## Verification

- `bundle exec rspec` (full suite, before the routing fix): 1 failure, `spec/openlanes/agents/routing_spec.rb:32`; coverage 99.14%.
- `bundle exec rspec spec/openlanes/agents/routing_spec.rb` after the fix: 22 examples, 0 failures.
- `bundle exec rubocop`: 847 files, no offenses.
- Not re-run: the full suite after the routing fix (it takes about 10 minutes, longer than this round had left).

## Building, round 1, continued (backend-coder)

- The repository's `.openlanes.yml` (recreated in `4fcb6eb2`) now says `frontend: true` and `desired_codebase_quality: high`, and `Config.current` read it from the suite's working directory. Besides `routing_spec.rb`, it also broke `dispatcher_spec.rb:523` (expected backend-coder alone) and 3 examples in `run_workflow_spec.rb`. Both specs now `chdir` to the fixture root, as `routing_spec.rb` does.
- `bundle exec rspec` (full, after the routing fix): 5936 examples, 7 failures: the 4 above, now fixed, plus 3 Redis outage specs (see `blocked.md` B1).
- `bundle exec rspec spec/openlanes/engine/dispatcher_spec.rb spec/openlanes/engine/run_workflow_spec.rb spec/openlanes/agents/routing_spec.rb`: 157 examples, 0 failures.
- `bundle exec rspec spec/openlanes/live/redis_outage_integration_spec.rb spec/openlanes/engine/redis_outage_spec.rb`: 4 examples, 2 failures (`can't modify string; temporarily locked` in `Live::Store#call`).
- `bundle exec rubocop`: 847 files, no offenses.

## Building, round 1, B1 answered (backend-coder)

B1 was answered `b)`: fix the Redis outage failures inside this plan.

- Cause: one `Live::Store` (one `RedisClient`) is shared by threads. The engine's `Outage` pings from the dispatcher tick while agent threads publish, and `RedisClient` is not thread-safe, so a call found the other thread's write buffer mid-use and raised `can't modify string; temporarily locked`.
- Fix: `lib/openlanes/live/store.rb` holds a `Monitor` around every command (`guarded`) and around `close`. A blocking `xread` holds it for the whole wait; the class comment says so.
- Spec: `spec/openlanes/live/store_spec.rb`, "answers callers on several threads at once" (8 threads × 200 set/ping). Failed before the fix with the same error, passes after.
- `bundle exec rspec spec/openlanes/live/store_spec.rb spec/openlanes/engine/redis_outage_spec.rb spec/openlanes/live/redis_outage_integration_spec.rb`: 34 examples, 0 failures.
- `bundle exec rspec` (full, after the Store fix): 5937 examples, 1 failure, 9 pending (Redis or tool skips); coverage 99.17%. The failure was `spec/openlanes/thread_safety_inventory_spec.rb:18`: the new `Monitor` in `live/store.rb` was not listed in `docs/thread-safety.md`. Added its row (guarded).
- `bundle exec rspec spec/openlanes/thread_safety_inventory_spec.rb spec/openlanes/live/store_spec.rb spec/openlanes/engine/redis_outage_spec.rb spec/openlanes/live/redis_outage_integration_spec.rb`: 38 examples, 0 failures. The only change since the full run is that one docs row, which only the inventory spec reads; the full suite was not re-run after it (about 10 minutes, longer than this round had left).
- `bundle exec rubocop`: 847 files, no offenses.

## Building, round 1, How to test (backend-coder)

- Added `## How to test` to `plan.md`, as the operator's mail asked. Nothing else in `plan.md` changed.
- `bundle exec rspec` (full, with the Store fix and the `docs/thread-safety.md` row): 5937 examples, 0 failures, 9 pending (Redis or tool skips); coverage 99.17%; exit 0.
- `bundle exec rubocop`: 847 files, no offenses.
