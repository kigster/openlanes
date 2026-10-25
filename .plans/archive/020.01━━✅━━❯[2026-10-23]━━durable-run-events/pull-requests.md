# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 105 | [\[020.01\](A) Durable Run Events](https://github.com/kigster/openlanes/pull/105) | Merged 🟣 |

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

## Answers, round 2 (rey-frontend)

chewie-verifier refused the commit for an edited `docs/badges/coverage_badge.svg`. HEAD already restored it (a3250ad9): `git diff origin/main -- docs/badges` is empty and the tree is clean. No front-end file is implicated; no code change. Did not run the suite, since a run rewrites the badge.

## Answers, round 2

chewie-verifier's "sent back for setup, verification round 1" is one top-level comment, not a review thread; `gh pr comment` is withheld, so the answer lives here.

- chewie-verifier round 1 (refused to commit: `docs/badges/coverage_badge.svg` edited): **fix**, already on the branch. `spec/spec_helper.rb:39` rewrites the badge on every rspec run, and `296143d2` carried that rewrite into the plan's commit. `a3250ad9` ("Restore the coverage badge from main") put it back; `git diff origin/main -- docs/badges` is now empty. After this round's suite run `git status --short` is empty too, so nothing outside the plan's files is left for the harness to commit.

Checks, 2026-10-21: `bundle exec rspec` → 4180 examples, 0 failures, 9 pending (web/dist missing); `bundle exec rubocop` → 572 files, no offenses.

## Answers, round 3

chewie-verifier's "rejected, verification round 3" (CI red on #105) is one top-level comment, not a review thread; `gh pr comment` is withheld, so the answer lives here.

- chewie-verifier round 3 (CI red): **fix**, ported. R2D2 fixed it on the remote branch in `1edd015b` ("Record a re-rejected PR as a second pr_reviewed event"); CI on remote head `cec4e2cf` is green (test, linter, web, e2e). The harness's rebase left the local branch without that commit, so a push of the rebased branch would have dropped it. Its `lib` and `spec` hunks are applied verbatim to the working tree, badge hunk excluded: `pr_reviewed` is keyed `[pr, rejection index]` counted from github mail; fixture `node-a.jsonl` fixture-11 verdict `rejected`. Files: `lib/openlanes/engine/pr_outcomes.rb`, `spec/fixtures/events/node-a.jsonl`, `spec/openlanes/events/pr_and_answer_emit_spec.rb`.

Checks, 2026-10-21: `bundle exec rspec` → 4265 examples, 0 failures, 9 pending (web/dist missing); `bundle exec rubocop` → 584 files, no offenses. `docs/badges` untouched after the run.

## Answers, round 4

No new review comment since chewie-verifier's round 3 (CI red), answered in round 3. CI on remote head `238c254a` is green (test, linter, web, e2e).

- Branch drift, **fix**: R2D2's merge of `origin/main` (`238c254a`) resolved the plan's two new `Time.now` calls onto the clock seam; the local rebased branch still had them. Now aligned: `lib/openlanes/engine/dispatcher.rb` (`@invocations[job.key] = @clock.now`) and `lib/openlanes/engine/runner.rb` (`mint_run` reads `Clock::System.now`). Every other plan file already matched the remote's patch.

Checks, 2026-10-23: `bundle exec rspec` → 4265 examples, 0 failures, 45 pending (36 need Redis at localhost:6379/15, which is not answering on this machine; 9 need web/dist). `bundle exec rubocop` → 584 files, no offenses. `docs/badges` untouched.

## Answers, round 5

hansolo-reviewer's "Review round 1… rejected 2/2" is one top-level conversation comment, not a review thread. `gh pr comment` is withheld, so the answer lives here.

- Finding 1 (the diff builds JSONL, but the spec asks for an ActiveRecord sink and a Reports page): no code change. This is a scope decision and it belongs to a human, as the finding itself says. It is asked as `blocked.md` B1, which offers a follow-up 020.02 as the recommended answer, and B2, which asks what the page reads from. Signed Blocked (product).
- Finding 2 (`plan.md` empty, contract stale): **fix**. `plan.md` now lists the as-built units B1–B6 and F1–F2 (the deleted plan, restored unchanged, since it matches the diff), plus a "Waiting on B1" section naming the database and Reports page work. In `contract.md`, an `amended:` note under the header says the contract describes the JSONL design as built and that the database interfaces will be written once B1 and B2 are answered. Files: `plan.md`, `contract.md`, `blocked.md`. No source file changed.

## Answers, round 5 (rey-frontend)

hansolo's round-1 re-review (top-level comment; `gh pr comment` withheld) has two findings. Finding 1 (JSONL vs the spec's AR sink, nav button and Reports page) needs a human ruling, as the review itself says: blocked.md B1, no code changed. Finding 2 (empty plan.md, stale contract.md) is luke-backend's; plan.md holds 17 KB here, contract.md is luke's to rewrite. No rebuttal, no fix from the front end.

## luke-backend, round 1 after D1 (2026-10-23)

hansolo's finding 1 is answered by D1 (b): the database sink and the Reports page are being built in this pull request. Finding 2: `plan.md` now has units B7 to B10 and F3 to F5, and `contract.md` has the D1 section, its amendments and its status, with `openapi.yaml` beside it. Built so far: B7, B8, and B10's reader and route. B9 and the D1 integration proof are still to do, so this round is signed "Almost completed", not "Completed".

## luke-backend, round 2 after D1 (2026-10-23)

Every back-end unit, B7 to B10, is built. This round added B9 (`Database::Loader`, `openlanes events migrate`, `openlanes events load`), the route spec, and the integration proof.

- `bundle exec rspec spec/integration/reports_api_spec.rb spec/openlanes/web/reports_api_spec.rb` → 4 examples, 0 failures. `GET /api/reports` reads the SQLite database, `exe/openlanes events report --format json` reads the JSONL log in its own process, and both give the same `result`.
- By hand, in a scratch repo with `events: { enabled: true, database: sqlite }`:
  - `exe/openlanes events migrate` printed the 4 migration versions.
  - `exe/openlanes events load` printed `0 events loaded, 0 already there; 0 plans and 12 agents synced`.
  - `events load -n` previewed the load and changed nothing.
- PostgreSQL was checked by hand against local PostgreSQL 18 on a scratch database, which was dropped afterwards. See `contract.md`, "Status (D1)".
- rey has not reported F3 to F5 done, so I am not last, and the repo's end-to-end suite was not run by me.

## Front end, round 2 (rey-frontend)

- `bundle exec rspec spec/integration/events_report_spec.rb spec/integration/reports_api_spec.rb` → 4 examples, 0 failures
- `bundle exec rspec` → 4327 examples, 0 failures, 45 pending
- `bundle exec rubocop` → 615 files, no offenses
- `cd web && npx vitest run` →       Tests  484 passed (484); `npm run lint` and `npm run typecheck` clean
- `web/cypress/e2e/reports.cy.ts` written (API intercepted); not run, it needs the demo server.

### Last to finish (luke-backend, round 2)

rey's mail #8 (18:55) says the front end is done, so these ran after both halves landed:

- `bundle exec rspec spec/integration/reports_api_spec.rb spec/integration/events_report_spec.rb spec/openlanes/web/reports_api_spec.rb` → 6 examples, 0 failures.
- `bundle exec rspec` → 4327 examples, 0 failures, 45 pending, exit 0. `bundle exec rubocop` → 615 files, no offenses, exit 0.
- `just web-e2e` (Cypress) was **not run**. The worktree has no `web/dist`, so it needs `just web-build` (an `npm` install and a build) first, and that did not fit in this round's time. `web/cypress/e2e/reports.cy.ts` is still unrun locally, so CI's `e2e` job is its first real run.
