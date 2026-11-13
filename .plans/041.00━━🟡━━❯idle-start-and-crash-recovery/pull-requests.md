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
