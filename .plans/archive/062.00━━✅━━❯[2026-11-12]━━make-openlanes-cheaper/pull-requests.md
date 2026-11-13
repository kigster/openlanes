# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 211 | [\[062.00\](A) Make Openlanes Cheaper](https://github.com/kigster/openlanes/pull/211) | Merged 🟣 |

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

## Findings: security-reviewer

no findings

## Answers, round 2 (backend-coder)

The review came as PR conversation comments, not inline threads, so there is no comment id to reply under; answered here.

- staff-reviewer ⛔️ / design-reviewer F201 (`executor.rb:538`): **fix**. `Executor#profile_for(agent, subject, root: @root)` measures `Vcs::DiffSize.lines(root)` in the checkout the agent runs in; `call`, `invocation`, `reattach` (its `restart["cwd"]`) and `prompt_for` pass their `root`. `Dispatcher#model_for` and `#profile_fields` pass `task.root`, so the board and `state.json` name the model actually run. Files: `lib/openlanes/execution/executor.rb`, `lib/openlanes/engine/dispatcher.rb`. Spec: `spec/openlanes/execution/executor_spec.rb` "choosing a small_diff model in a plan worktree" (main tree 12 lines, worktree 900 → opus through `Executor#call`); two of its three examples fail with the old `@root`.
- F202 (`dispatcher.rb:1038`): **fix**, partly. `over_budget?` is now `budget_refusal` (a query) and `announce_budget` (says it once); `budget_holds` uses the same query. Moving the hold out of `dispatcher.rb` was not done this round.
- F203 (`budget.rb:29,40`): **fix**. `Budget.read(dir)` is the one reader of the log for both constructors; `Budget.for` asks the sink `enabled?` instead of `respond_to?(:dir)`. The board still reads a log a disabled run left behind while the cap is not enforced: contract A1, kept on purpose.
- F204 (`live/snapshot.rb:52`, `live/publisher.rb:38`): **fix**. `Engine.budget`, `Engine.budget_for(runner)` and `Engine.no_budget` are on the facade; `Live` and `Dispatcher` go through them.
- staff Hmmm `prompt.rb:374` (`since_round: round - 1`): not changed this round; left open.
- staff Hmmm `dispatcher.rb:1049` (O(plans × events)): **rebuttal** for now: the reviewer says "Fine today", and the events are cached for `Budget::TTL` seconds.

### Checks, round 2 (backend-coder)

- `bundle exec rubocop`: 856 files inspected, no offenses detected.
- `bundle exec rspec spec/openlanes/{engine,live,integration,execution}`: 1951 examples, 0 failures.
- `bundle exec rspec` on every other spec file: 4029 examples, 1 failure (`architecture_doc_spec.rb:13`, stale after the `Engine` facade methods); `just update-architecture` regenerated `docs/architecture/openlanes-{engine,live}.md`, then `spec/openlanes/docs`: 5 examples, 0 failures.
- A single whole-suite run did not finish inside the 10-minute background cap with other suites running on the machine, so the suite was run in the two halves above.
