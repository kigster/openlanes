# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 105 | [\[020.01\](A) Durable Run Events](https://github.com/kigster/openlanes/pull/105) | Open 🟡 |

## Integration proof (rey-frontend, round 1)

- `bundle exec rspec spec/integration/events_report_spec.rb` → 2 examples, 0 failures. Real Runner round, real Unblocker, PrWatch/PrOutcomes with a GitHub double, then `exe/openlanes events report --format json` as a subprocess.
- `bundle exec rubocop` → 460 files, no offenses.
- `bundle exec rspec` → 3224 examples, 30 failures, all under `spec/openlanes/apps/` (Probe/Ports/Runner/Supervisor/Restart, `app_spec`). Cause in this sandbox: a closed port reads as listening (`probe_spec.rb:41`). No file under `apps/` is touched by this plan. Luke's baseline showed 1 failure in the same area.

## Integration proof (luke-backend, last, round 1, 2026-10-20)

B1 was answered "rebase onto main and retry". `git rebase` is withheld from agents, and the harness had not rebased (the branch is still at `9a87460d`), so the main fix the answer points at, `ff03ca48` ("Fixing a bug in port detection": `Probe.listening?` asks the socket for its peer), is applied verbatim to `lib/openlanes/apps/{ports,probe}.rb`, `spec/fixtures/apps/servers/server.rb`, `spec/openlanes/apps/{probe,supervisor}_spec.rb` and `spec/openlanes/cli/app_spec.rb`. The hunks are identical to main's, so the rebase drops them cleanly.

- `bundle exec rspec spec/integration/events_report_spec.rb` → 2 examples, 0 failures.
- `bundle exec rspec spec/openlanes/apps spec/openlanes/cli/app_spec.rb` → 113 examples, 0 failures.
- `bundle exec rspec` → 3225 examples, 0 failures, 9 pending. The 9 pending specs skip themselves with "web/dist is missing: run just web-build first".
- `bundle exec rubocop` → 460 files inspected, no offenses detected.
- `just web-e2e` (Cypress) was not run. This plan changes no file under `web/`, and this worktree has no `web/node_modules` or `web/dist`. Building them takes an `npm` install.

## Integration proof (rey-frontend, re-run)

- `bundle exec rspec` → 3225 examples, 0 failures, 9 pending; `bundle exec rubocop` → no offenses; events CLI, presentation, integration and docs specs → 15 examples, 0 failures.

## Answers, round 1 (rey-frontend)

No review comment names a front-end file. Both findings (`human_answered` id collapse in `unblocker.rb`/`sink.rb`; `blocks` count in `report.rb`/`dispatcher.rb`) belong to luke-backend's half; mailed luke. No rebuttal or fix from the front end.

## Answers, round 1

hansolo's findings sit in one top-level conversation comment (id 6305090921), not in review threads, so there is no thread to reply in; `gh pr comment` is withheld. Both are fixes.

- 6305090921, finding 1 (`human_answered` ids collide across blocks): **fix**. `Unblocker#drain` digests `blocked.md` before the drain and keys each answer by `[digest, number]` instead of the number alone, still with `once: true`. A re-block's B1 gets a new id; two runs draining the same file still dedupe to one. Files: `lib/openlanes/lifecycle/unblocker.rb`; specs in `spec/openlanes/events/pr_and_answer_emit_spec.rb` ("keeps a re-block's B1 answer apart…", "dedupes the same drain seen by two runs").
- 6305090921, finding 2 (`blocks` counted signings): **fix**. `Report#call` sums `payload["blocks"]` per `block_raised` (an event without a count is 1), and time-to-answer pairs each of a block's questions with its own answer. Files: `lib/openlanes/events/report.rb`; spec in `spec/openlanes/events/report_spec.rb` ("when one Blocked signing leaves B1, B2 and B3 open": blocks 3, runs_needing_feedback 1, 3 answers). Fixture `spec/fixtures/events/node-b.jsonl` now says `blocks: 1` for 021.00, so the fixture still totals 3 blocks over 2 runs.

Checks, 2026-10-20: `bundle exec rspec` → 4089 examples, 0 failures, 9 pending (web/dist missing). `bundle exec rubocop` → 551 files, no offenses. `bundle exec rspec spec/integration/events_report_spec.rb` → 2 examples, 0 failures.
