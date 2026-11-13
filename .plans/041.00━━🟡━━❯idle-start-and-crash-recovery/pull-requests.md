# Pull Requests

- #146 Run each agent under an openlanes-agent supervisor (merged 2026-10-26)
- #147 Reattach the engine to agents a dead engine left (merged 2026-10-27)
- #148 Pause agents gracefully on a system stop (merged 2026-10-27)

## Checks, round 1 (2026-11-12, main at 4fcb6eb2, nothing changed)

- `bundle exec rubocop`: 847 files inspected, no offenses detected, exit 0.
- `bundle exec rspec`: 5936 examples, 9 failures, 9 pending. All 9 are outside this plan; see `blocked.md` B1.

## Checks, round 3 (2026-11-12, main at 4fcb6eb2, nothing changed)

- `bundle exec rubocop`: 847 files inspected, no offenses detected, exit 0.
- `bundle exec rspec`: 5936 examples, 9 failures, 9 pending. These are the same 9 baseline failures as round 1 (routing_spec x3, dispatcher_spec:523, run_workflow_spec x3, redis_outage_spec:37, live/redis_outage_integration_spec:72).
- B1 answered a): those failures get fixed in a separate plan, and 041 goes to review as it is. No frontend units, so frontend-coder was not started.

## Checks, round 5 (2026-11-12, main at 1c39173d, nothing changed)

- `bundle exec rubocop`: 867 files inspected, no offenses detected, exit 0.
- `bundle exec rspec`: 6037 examples, 6 failures, 9 pending, coverage 99.17%. All 6 come from the local environment, the same class of leak as B1, and none from plan 041's code:
  - `cli/web_spec.rb:255,277` and `cli/engine_command_spec.rb:289,317`: `OPENLANES_ADMIN_CREDENTIALS` is set in the shell and leaks a login into specs that expect none. Rerunning those two files: 84 examples, 4 failures.
  - `live/redis_outage_integration_spec.rb:77,100`: `REDIS_URL` points at a non-local Redis (B1).
- Per B1 a), spec isolation from the environment belongs in a separate plan. Add `OPENLANES_ADMIN_CREDENTIALS` to it.
