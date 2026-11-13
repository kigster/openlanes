# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 223 | [\[060.00\](A) Improve Openlanes Low Hanging Fruit](https://github.com/kigster/openlanes/pull/223) | Open 🟡 |

## Round 1, backend-coder

- Baseline on clean HEAD (before this plan): `spec/openlanes/agents/routing_spec.rb` lines 19, 32, 42 fail; `spec/openlanes/live/redis_outage_integration_spec.rb:77` fails. Not caused by this plan.
- B3 done: `Plans::UnitSizes`, `Agents::Sizing` (`.openlanes.yml` `sizing:`), `Spec#unit_size`, Profile precedence step 3, Fable 5.2 catalogue entry, ceiling lifted only for a `sizing:`-configured model, planner.md `**Size:**` field. `bundle exec rubocop`: 0 offenses. `docs/architecture/` regenerated.
- Not started: B5a, B5b, B1, B4, B2, B6. `openlanes docs` / `just update-workflow` not yet re-run for the `**Size:**` field.

## Round 2, backend-coder

- B1 done: `Engine::ReviewPacket` (diff + digest built once per plan and head sha, `MAX_DIFF` cap with a truncation note), `Vcs::GitHub#pr_diff`, `Execution::Prompt` injects the packet for review-phase agents only; staff/security/design-reviewer briefs read the packet first. Specs: `review_packet_spec.rb`, `prompt_review_packet_spec.rb`. Cache row added to `docs/thread-safety.md`.
- B3 docs: `openlanes docs` now lists `**Size:**` (documentation.rb); `docs/WORKFLOW.md` regenerated (gitignored).
- Fixed baseline `routing_spec.rb` failures: the spec read this repo's own `.openlanes.yml` (`frontend: true`).
- Still red, and red on clean HEAD too, for the same `.openlanes.yml` leak: `dispatcher_spec.rb:523`, `run_workflow_spec.rb:115, :226, [1:2:6]`. `redis_outage_integration_spec.rb:77, :100` are timing-flaky (pass alone).
- `bundle exec rubocop`: 0 offenses.
- Not started: B5a, B5b, B4, B2, B6.

## Round 3, backend-coder

- Fixed the remaining `.openlanes.yml` leak: `dispatcher_spec.rb` and `run_workflow_spec.rb` now run from the fixture root (135 examples, 0 failures). This edits `dispatcher_spec.rb` before B5a, so B5a's "dispatcher specs unchanged" baseline is this round's version.
- B4 finding (for the PR body): nothing handles a provider rate limit today. `Executor#lost_session` retries only a *resumed* session that failed before spending anything (which covers an overload at start-up), and `dispatcher_outage_spec.rb` is about Redis, not the provider. A mid-run 429/529 is reported as an ordinary failure and costs an attempt.
- B4 part 1 done: `Execution::RateLimit.detect(status, transcript)` (429, `rate_limit_error`, `overloaded_error`, 529, `retry_after`), `#delay` (30 s doubling to a 900 s cap, up to 25% jitter, `retry_after` wins), `#phrase` for the board. Spec: `rate_limit_spec.rb`, 12 examples green. Rubocop clean on the touched files.
- B4 still to do: `Executor::Result#rate_limit` set from `verdict`, then the requeue in `steps/settle.rb` (after B5b).
- The full suite was not re-run this round (the background run was killed).

## Round 4, backend-coder

- B4 part 2 done: `Executor::Result#rate_limit` / `#rate_limited?`; `Executor#verdict` runs `RateLimit.detect` after the kill check and before the exit-status check, so a mid-run 429/529 comes back as its own outcome ("claude was turned away (rate_limited): …"). Three new examples in `executor_spec.rb` ("when claude exits non-zero"); `spec/openlanes/execution`: 477 examples, 0 failures. Rubocop clean on the touched files.
- B4 still to do: `Dispatcher#settle` still treats a rate-limited result as `!result.ok` (an attempt). The requeue with `RateLimit#delay`, the board phrase and the pause across all jobs belong in `steps/settle.rb`, after B5b.
- Full `bundle exec rspec` from round 4 (finished after signing): 5983 examples, 4 failures, exit 1.
  - `architecture_doc_spec.rb:13`: stale after `rate_limit.rb` and the `Executor::Result` change. Fix with `just update-architecture`.
  - `redis_outage_integration_spec.rb:72, :100`: timing-flaky, as in earlier rounds.
  - `apps/restart_spec.rb:77`: not yet investigated. Run it alone to see whether it is flaky.

## Round 5, backend-coder

- `just update-architecture` re-run; `architecture_doc_spec.rb` green.
- `apps/restart_spec.rb:77` passes when run alone (6 examples, 0 failures): timing under a loaded machine.
- The flaky `redis_outage_integration_spec.rb` was a real race: `Live::Store` shared one RedisClient across the tick, agent jobs and PR watch, and interleaved commands raised "can't modify string; temporarily locked". Every command now takes a `Monitor`, and the blocking XREAD has its own client behind its own lock. Before: 2 of 3 runs failed. After: 3 of 3 runs green; `spec/openlanes/live` 626 examples, 0 failures. Row added to `docs/thread-safety.md`.
- Full `bundle exec rspec` this round: 5986 examples, 4 failures, all in `cli/web_spec.rb:255, :277` and `cli/engine_command_spec.rb:289, :317`. The operator's shell exports `OPENLANES_ADMIN_CREDENTIALS`, and the suite inherited it. `spec_helper.rb` now deletes it at load, beside `NO_COLOR`; both files then ran 84 examples, 0 failures. No other failures in that run, so the suite should now be green. Not confirmed by a second full run.
- `bundle exec rubocop`: 857 files, 0 offenses.
- Units still open: B5a, B5b, B4 settle requeue, B2, B6.
