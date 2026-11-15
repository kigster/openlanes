# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 243 | [\[045.02\](A) Split Dispatcher](https://github.com/kigster/openlanes/pull/243) | Merged 🟣 |

None yet: U1 (Desk) built in round 1; U2 to U8 remain.

## Round 3 full suite (after U1, U2 and the architecture regen)

`bundle exec rspec`: 6157 examples, 0 failures, 9 pending, coverage 98.41%, 9 min 56 s. The process was killed by a 10-minute background limit after rspec printed its summary, so its exit code was not captured.

## Round 4 full suite (after U3)

`bundle exec rspec`: 6563 examples, 1 failure, 9 pending, coverage 99.23%, exit 1. The failure was `architecture_doc_spec.rb:13` (docs stale after the new `assign/` classes); `just update-architecture` was rerun and that spec now passes (2 examples, 0 failures). `bundle exec rubocop`: exit 0.

## Round 5 full suite (after U4)

`bundle exec rspec`: 6569 examples, 0 failures, 9 pending, coverage 99.25%, exit 0, 9 min 2 s. `bundle exec rubocop`: 1012 files, no offenses, exit 0.

## Round 6 (U5)

`bundle exec rubocop`: 1023 files, no offenses, exit 0. Dispatcher-area specs: 994 examples, 0 failures. `rg "public_send|method_missing|send\(" lib/openlanes/engine/dispatcher*` prints nothing. Two hits remain elsewhere in `lib/openlanes/engine` (`rebase.rb:188`, `run_workflow.rb:782`), outside this plan's files. Full suite started; summary in `/tmp/045.02-r6-full.txt`, no EXIT line.

## Round 7 (U6)

Round 6 full suite: 6574 examples, 0 failures, 9 pending, coverage 99.25%. After U6: dispatcher, live, runner and integration specs 1071 examples, 0 failures; `bundle exec rubocop` 1035 files, exit 0. Full suite running into `/tmp/045.02-r7-full.txt`.

Round 7 full suite: 6580 examples, 1 failure, 9 pending, coverage 99.26%, exit 1. The failure was `dependencies_spec.rb:335`, a 5-second wall-clock assertion on a 50,000-plan chain in a file this plan does not touch; rerun alone it passes in 2.51 s, so it was machine load (files took 7.79 s to load in that run).

## Round 8 (U7, part of U8)

U7 split done: `poll/{sighting,mail,journal}.rb`, `lanes/{discards,copilot}.rb`, `rows/active.rb`, `rulings.rb` helpers, plus `settle/account.rb` and `start.rb` fixes that the todo entries had hidden. New specs for those classes: 21 examples, 0 failures. Removed from `.rubocop_todo.yml`, every `lib/openlanes/engine/dispatcher*` entry: Metrics/AbcSize (10: dispatcher.rb, assign, desk, lanes, poll, rename, rows, rulings, settle, start), Metrics/ClassLength (6: dispatcher.rb, assign, desk, rename, settle, start), Metrics/MethodLength (10, same files as AbcSize), Metrics/ParameterLists (2: dispatcher.rb, desk). `rubocop` on the dispatcher: 69 files, 0 offenses. `public_send` removed from `rebase.rb` (literal token readers) and `run_workflow.rb` (literal info/warn); `rg "method_missing|public_send|send\(" lib/openlanes/engine` prints nothing; rebase and run specs 126 examples, 0 failures.

Round 8 full suite (started after U7 code, before the U7 specs and the public_send fixes): 6580 examples, 0 failures, 9 pending, coverage 99.26%, exit 0.

## Round 9 (U8 integration spec)

`spec/openlanes/engine/dispatcher_split_integration_spec.rb` drives a real `Runner` through the real `Dispatcher` under `--isolation shared` with a scripted executor: plan 001.00 is planned and moves 📋 → ⭐ → 🟡 (planner Completed, then backend-coder started), plan 002.00 blocks (planner writes `blocked.md` and signs Blocked). It records the folder names before each tick, the `state.json` signatures, `blocked.md`, the attempts and the board text, and compares them with `spec/fixtures/dispatcher_split/run.yml`. That fixture was captured by running the same spec with `OPENLANES_CAPTURE_FIXTURE=1` in a detached worktree at this branch's HEAD (6a60b1f0, the pre-split main tip; `origin/main` in this checkout was stale at c9514793), then removed. On the split the spec passes against it: 1 example, 0 failures.

## Round 10 (final checks)

`bundle exec rubocop`: 1050 files inspected, no offenses detected, exit 0. Every file under `lib/openlanes/engine/dispatcher*` is at most 100 lines by `wc -l`; `.rubocop_todo.yml` has no `lib/openlanes/engine/dispatcher` entry; `rg "method_missing|public_send|send\(" lib/openlanes/engine` prints nothing.

## Round 11 (final checks)

`bundle exec rubocop`: 1050 files inspected, no offenses detected, exit 0.
`bundle exec rspec`: 6602 examples, 0 failures, 9 pending, coverage 99.26% (main before the split: 99.25%), exit 0. Both run after the last edit.

## Findings: staff-reviewer

CI was still running (circleci linter, test, web, e2e pending) when this review was written.

### F1 [minor] lib/openlanes/engine/dispatcher/desk/rounds.rb:36

The spec's Goal is "≤ 4 parameters", but two Desk methods still take more, and an inline `rubocop:disable Metrics/ParameterLists` hides them: `Desk::Rounds#remember(ordinal, agent, state, status, round)` (5) and `Desk::RoundRecords#harness_resume(subject, agent, round, reason, last:, phrase:)` (6, `desk/round_records.rb:16`). The U1 journal said "Revisit in U8", and U8 never did. The plan's How to test says the dispatcher files are "linted at the real limits now", which is not true for these two. Scenario: input `rg -n "rubocop:disable" lib/openlanes/engine/dispatcher*`. Expected: nothing, since every dispatcher method is at ≤ 4 parameters. Actual: two hits. Suggested fix: pass a value (for example `Desk::Stamp = Data.define(:ordinal, :agent, :state, :status, :round)`), or record the exception in the PR body as a deliberate one.

### F2 [minor] lib/openlanes/engine/rebase.rb:185

Two files outside the spec's `Files:` list (`rebase.rb`, `run_workflow.rb`) were edited to satisfy the plan's `rg … lib/openlanes/engine` check, which narrows the spec's own check (`rg … lib`, with an allow list). Both rewrites keep behaviour. The narrowing still leaves the spec check unmet: `rg "method_missing|public_send|send\(" lib` still hits `support/log.rb:188`, `support/config.rb:242`, `support/ui.rb:631` and others. Scenario: run the spec's check as written. Expected: no hit off the allow list. Actual: about 10 hits, none of them on a list this plan names. Either state in the PR body that the lib-wide check belongs to a later 045 child, or drop the two out-of-scope edits.

## Findings: security-reviewer

no findings

Checked: no new shell, SQL, path, regex or env input; the only `File` use is a join of a plan folder path with the fixed name `blocked.md`; the `public_send` replacements in `rebase.rb` and `run_workflow.rb` use literal readers over fixed names; no secrets in code, logs or fixtures; no dependency added or bumped.

## Answers, round 12

Both findings sit in staff-reviewer's issue comment on #243 (id 6884819831), not in review threads, so there was no `/replies` endpoint to answer in; the answers were posted as one issue comment on the pull request (id 6885981839, https://github.com/kigster/openlanes/pull/243#issuecomment-6885981839). No code changed in this round.

- F1 (issue comment 6884819831): rebuttal, with plan.md's How to test corrected. `Desk::Rounds#remember` (5 parameters) and `Desk::RoundRecords#harness_resume` (6) keep their inline `rubocop:disable Metrics/ParameterLists`, recorded as deliberate: they are the only two such disables in the 69 dispatcher files, each carries its reason on the line, and `.rubocop.yml` sets `Max: 4` with keyword arguments counted. They are the Desk's positional contract, written by the steps from 15 (`remember`) and 4 (`harness_resume`) call sites. A `Desk::Stamp = Data.define(...)` would move the five arguments into a constructor at every call site without reducing what a caller supplies, and would lengthen files U1 to U7 brought to at most 100 lines. plan.md no longer says "linted at the real limits" without qualification; it names the two exceptions and the `rg` that prints exactly those two lines.
- F2 (issue comment 6884819831): rebuttal. The lib-wide `rg "method_missing|public_send|send\(" lib` check belongs to a later 045 child. spec.md's `Files:` names `dispatcher.rb` and `dispatcher/` only, and plan.md's U8 narrowed the check to `lib/openlanes/engine` so the dispatcher's own namespace is clean. The `rebase.rb` and `run_workflow.rb` edits fall inside that narrowed scope, keep behaviour (security-reviewer confirmed the literal readers), are covered by the rebase and run specs (126 examples, 0 failures) and are already on `main` through #243, so dropping them now would be a revert for no gain. The 21 hits left outside `lib/openlanes/engine` (`support/log.rb:188`, `support/config.rb:246`, `support/ui.rb:631`, `agents/routing.rb:100`, `live/commands.rb:233` and others) are dynamic dispatch over fixed tables in other namespaces, each needing its own allow-list decision in the child that owns those files. plan.md's How to test now says so.

Checks run after the last edit, round 12 (no code changed; HEAD is `origin/main` plus the harness's `.plans` commit):

```
bundle exec rubocop   # 1120 files inspected, no offenses detected
bundle exec rspec     # 6957 examples, 0 failures, 10 pending, coverage 99.19%, 11 min 51 s
```

The wrapper that ran both exited 0. The example count and coverage moved from round 11 (6602, 99.26%) because main was merged into the branch before #243 landed.
