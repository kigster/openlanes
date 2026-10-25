# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 111 | [\[035.00\](A) Three Quality Levels](https://github.com/kigster/openlanes/pull/111) | Open 🟡 |

## Verification, round 3 (luke-backend)

- `bundle exec rspec`: 3999 examples, 0 failures, 9 pending (`web/dist is missing: run just web-build first`, environmental)
- `bundle exec rubocop`: 527 files inspected, no offenses detected
- No integration proof or e2e suite: rey is not started (`## Frontend` has no units).

## Answers, round 4 (luke-backend)

hansolo's review arrived as one PR conversation comment, not inline review comments (`gh api .../pulls/111/comments` returns none), so there are no threads to reply in. Each finding, answered here:

1. Quality gate starves the integration fixtures: **fix**. `ControlRoomProcess.checkout` (`spec/support/control_room_process.rb`) now writes `desired_codebase_quality: high` to the checkout's `.openlanes.yml`. Every failing spec (`two_checkouts`, `control_room`, `restart`) builds its root through it.
2. Stale `@param answer` doc: **fix**. `lib/openlanes/plans/plan_state.rb` now reads `"high", "standard" or "mvp"`.

## Verification, round 4 (luke-backend)

- `just web-install && just web-build`: built `web/dist`
- `bundle exec rspec spec/integration`: 55 examples, 0 failures (none pending)
- `bundle exec rspec`: 4090 examples, 0 failures, 0 pending
- `bundle exec rubocop`: 548 files inspected, no offenses detected

## Answers, round 5 (luke-backend)

hansolo's round-2 review is again one PR conversation comment, with no inline threads to reply in.

1. `docs/WORKFLOW.md` contradicts the state machine: **fix**. Ran `just update-workflow`; `docs/WORKFLOW.md` now has `in_review --> building` in the mermaid diagram and the 👀 row reads `🟡 🧪 ✅ 🔴 💩 ❌`. No other line changed.

## Verification, round 5 (luke-backend)

- `bundle exec rubocop`: 560 files inspected, no offenses detected
- `bundle exec rspec` (with `web/dist` built): 4174 examples, 0 failures, 0 pending

## Answers, round 6 (luke-backend)

`gh api repos/kigster/openlanes/pulls/111/comments` returns no inline comments, so there are no threads to reply in. Every non-✅ item in the review bodies, answered:

1. hansolo round 2, `docs/WORKFLOW.md` stale: **fix**, already on the branch in `c7145e92` (regenerated) and `a9e1bf12` (`starts:`). The committed file has `in_review --> building`, and its 👀 row lists 🟡. The working tree held an uncommitted copy left over from the `lane:` era that would have undone `a9e1bf12`. I put it back to `HEAD` (`git checkout -- docs/WORKFLOW.md`), so the harness doesn't publish a regression.
2. Grok/trio 💩, branch conflicts with `main`: **fix**, rebased in `0879f57b` (reply of 2026-10-22).
3. Grok/trio 🤔, mvp verdict reads "verified": **fix**, `c7145e92` writes `Verdict: skipped (mvp)` and parses it as `:skipped`.
4. Grok 🤔, send-back signed "approved": **fix**, `c7145e92` signs a return to 🟡/🔴 as "sent back".
5. Grok 🤔, the gate waits silently with nobody in scope: **fix**, `c7145e92` logs it and sets an idle reason.
6. opsec 🤔, `awaiting_ci?` accepts `:skipped` under any quality: **fix**, `9cdcbdf9`.
7. opsec 🤔, `outcome.rb#settle` treats CI `:none` as gated: **rebuttal**. That code is on `main`, outside this PR, and #103's `Engine::Merging` already refuses to auto-merge a PR with no checks (answered 2026-10-22).
8. Grok 🤔, "`high` and `standard` behave the same in the engine": **rebuttal**. They differ where M5's first row says they should. `Outcome::SEND_BACK` sends a `review-ok-not-perfect` PR to 🟡 under `standard` and to 🔴 under `high` (`spec/openlanes/engine/verification/outcome_spec.rb`). Equal `max_rejections` (2 and 2) is plan U1's choice. M5 has no `max_rejections` row; its "Default Number of Build Rounds" row (2/2/3) is not wired, like the depth row above it. That is a question for the spec's author, not a defect in this PR.

## Verification, round 6 (luke-backend)

- `bundle exec rubocop`: 565 files inspected, no offenses detected
- `bundle exec rspec` (with `web/dist` built): 4207 examples, 0 failures, 45 pending. All 45 are the Redis-backed specs skipping with `no Redis answers at redis://localhost:6379/N`, because this sandbox can't reach Redis. That is environmental, not caused by this branch.

## Answers, round 7 (luke-backend)

No review has landed since round 6: the last conversation comment is the 2026-10-22 reply, and `gh api repos/kigster/openlanes/pulls/111/comments` still returns no inline threads. Round 6's eight answers stand. Round 6 was interrupted by a harness error after the answers were written, so this round re-checks the branch, which the harness has since rebased onto `main` (`cdb57836`, #113). The local head is `0673509d`; the PR head on GitHub is still the pre-rebase `7c5cff61`.

## Verification, round 7 (luke-backend)

- `bundle exec rubocop`: 565 files inspected, no offenses detected
- `bundle exec rspec` (with `web/dist` built): 4222 examples, 0 failures, 45 pending. All of the pending specs are Redis-backed and skip with `no Redis answers at redis://localhost:6379/N`, because Redis is unreachable from this sandbox.
