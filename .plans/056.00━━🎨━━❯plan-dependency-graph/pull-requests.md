# Pull Requests

## backend-coder, round 1

- `bundle exec rspec`: 5949 examples, 8 failures; 7 pre-existing at `4fcb6eb2` (blocked.md B1), 1 (`architecture_doc_spec.rb:13`) fixed by `just update-architecture` and rerun green.
- `bundle exec rubocop`: 849 files inspected, no offenses.
- `docs/WORKFLOW.md` is not tracked in this repository, so the regenerated copy was not added; `openlanes docs` lists `summary:` (documentation_spec).

## backend-coder, round 3 (after the Redis race question was answered: ship as is, race fixed in PR #206)

- `bundle exec rubocop`: 851 files inspected, no offenses.
- `bundle exec rspec spec/openlanes/web/dependency_graph_spec.rb spec/openlanes/web/app_spec.rb spec/openlanes/plans/spec_spec.rb spec/openlanes/presentation/documentation_spec.rb spec/openlanes/checkout_config_spec.rb spec/openlanes/agents/routing_spec.rb`: 216 examples, 0 failures.
- Full `bundle exec rspec`: had not finished after 11 minutes, with another agent's rspec running on the same machine. That fits the `Live::Store` Redis race that PR #206 fixes, but this round did not confirm it. Not run to completion this round.
- Cypress (`web/cypress/e2e/dependencies.cy.ts`) not run this round.

## Frontend integration proof, round 1

- `npx vitest run` (Node 22): 56 files, 553 tests pass. Node 26 from Volta breaks `localStorage` in jsdom; environmental.
- `npm run typecheck` and `npx eslint .` in `web/`: clean.
- `npm run build`, then `bin/web-e2e` limited to `cypress/e2e/dependencies.cy.ts`: 4 passing, 0 failing. Fix made on the way: the filter's off-by-default keys were `done`, which is not a real state; now the archived states (`approved`, `deployed`, `deferred`, `abandoned`, `discarded`, `trashed`).
- `bundle exec rubocop`: 851 files, no offenses.
- `bundle exec rspec`: see the signing note; backend-coder reported flaky Live::Store Redis specs outside this plan.
- Correction: the full `bundle exec rspec` did finish: 5952 examples, 5 failures, 7 pending.
  - `spec/openlanes/live/redis_outage_integration_spec.rb:100`: the `Live::Store` race (PR #206).
  - `spec/openlanes/cli/web_spec.rb:255,277` and `spec/openlanes/cli/engine_command_spec.rb:289,317`: the shell had `OPENLANES_ADMIN_CREDENTIALS` set. `env -u OPENLANES_ADMIN_CREDENTIALS bundle exec rspec spec/openlanes/cli/web_spec.rb spec/openlanes/cli/engine_command_spec.rb` gives 84 examples, 0 failures. The suite does not clear that variable, so these 4 fail on any machine that sets it.
- `bundle exec rspec`: 4 failures, none in this plan's files, coverage 99.18%. `redis_outage_integration_spec.rb:72` is the flaky Live::Store race backend-coder reported. `cli/web_spec.rb:255`, `:277` and `cli/engine_command_spec.rb:317` read the admin credentials (`user="kig"`) and a LAN address from the checkout's uncommitted `.openlanes.yml`, the same leak backend-coder's `spec/support/checkout_config.rb` fixes for other specs. A reviewer should run them on a clean checkout.
