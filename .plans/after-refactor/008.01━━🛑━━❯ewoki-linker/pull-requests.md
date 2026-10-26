# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 114 | [008.01 🔗 ewoki-linker: link state and link command](https://github.com/kigster/openlanes/pull/114) | Open 🟡 |

## Checks, round 1 (backend-coder)

- `bundle exec rubocop`: 441 files inspected, no offenses detected
- `bundle exec rspec`: 3177 examples, 30 failures, 9 pending; all 30 in `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb` (machine answers every local port, see `blocked.md` B1)
- `bundle exec rspec spec/openlanes/{plans,evals,agents,engine,execution} spec/openlanes/vcs/mainline_spec.rb spec/openlanes/cli/link_spec.rb spec/openlanes/lifecycle/linker_spec.rb spec/openlanes/cli/help_spec.rb`: 1194 examples, 0 failures
- `./exe/openlanes agents list`: `ewoki-linker │ precedes ready_for_planning, planned │ in place`
- integration proof `spec/openlanes/cli/link_spec.rb`: `link --dry-run` prints `would invoke ewoki-linker for 050.00` and nothing for the `[none]` plan; refuses in a linked worktree and off `main`
- `./exe/openlanes evals ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS; `--recording fail` fails all three

## Checks, round 1 resumed after B1 (backend-coder, 2026-10-21)

B1 answered (b): the 30 `apps/` failures are accepted as outside this plan (plan.md D5). Re-run after the harness restart:

- `bundle exec rubocop`: 441 files inspected, no offenses detected
- `bundle exec rspec`: 3177 examples, 30 failures, 9 pending; filtering the failure list for anything outside `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb` prints nothing
- `./exe/openlanes agents list`: `ewoki-linker │ precedes ready_for_planning, planned │ in place │ haiku/low`
- `./exe/openlanes evals ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS
- `docs/badges/coverage_badge.svg` reverted; the suite rewrites it on every run

## Checks after the harness rebase onto `main` 667bcf0e (backend-coder, 2026-10-21)

Branch `kig/008.01-spec-ewoki-linker`, HEAD `338804aa Ewoki Linker`. The previous publish failed with `src refspec kig/008.01-ewoki-linker does not match any`: the harness pushed a branch name that differs from the worktree's branch.

- `bundle exec rubocop`: 565 files inspected, no offenses detected
- `bundle exec rspec`: 4213 examples, 0 failures, 9 pending (the B1 port failures no longer occur)
- `./exe/openlanes agents list`: `ewoki-linker │ precedes ready_for_planning, planned │ in place │ haiku/low`
- `./exe/openlanes evals ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS
- integration proof `bundle exec rspec spec/openlanes/cli/link_spec.rb`: 3 examples, 0 failures

## Round 2 (backend-coder, 2026-10-21): the branch the publisher pushes

Round 1 ended Completed but the plan stayed at 🟡, because 🟢 needs an open pull request and the publish failed with `src refspec kig/008.01-ewoki-linker does not match any`. Cause: this worktree was reused and still had `kig/008.01-spec-ewoki-linker` checked out, the head of spec PR #29, already merged. `Worktree#branch_for` derives `kig/008.01-ewoki-linker`, which did not exist. A push to the merged branch would have landed nowhere.

- `git switch -c kig/008.01-ewoki-linker` at `338804aa` (HEAD's SHA unchanged). `kig/008.01-spec-ewoki-linker` is left as it was, locally and on `origin`.
- To undo: `git switch kig/008.01-spec-ewoki-linker && git branch -D kig/008.01-ewoki-linker`.
- Harness follow-up, not done here: `Worktree#checkout_for` reuses an existing directory without checking that its branch is `branch_for(feature)`.
- `bundle exec rubocop`: 565 files, no offenses. `bundle exec rspec`: exit 0, 4213 examples, 0 failures, 9 pending. `agents list`: `ewoki-linker │ precedes ready_for_planning, planned`. `evals ewoki-linker`: 3/3 PASS.

## Round 1 after the OAuth interruption (backend-coder, 2026-10-23)

- The worktree is now on `kig/eval-agent-positional` (`6d04fb82`, PR #122), switched there by kig on 2026-10-23. `kig/008.01-ewoki-linker` still points to `0398136d`.
- `6d04fb82` says the rest of `0398136d` is superseded by PR #114 (`kig/ewoki-linker`, open), which implements this plan.
- I built nothing, published nothing and changed no branch. Blocked (technical): see `blocked.md` B1 for which pull request belongs to this plan.

## Round 1 after B1 (backend-coder, 2026-10-23): PR #114 adopted

B1 answered (a): PR #114 (`kig/ewoki-linker`, head `36c8f690`) is this plan's pull request, recorded in the table above. `kig/008.01-ewoki-linker` (`0398136d`) stays unpublished. No code changed in this round.

Checks against #114, read-only in `openlanes.worktrees/ewoki-linker`:

- CircleCI on `36c8f690`: linter, test, web, e2e all SUCCESS
- `./exe/openlanes eval --agent ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS
- `./exe/openlanes agents list`: `ewoki-linker │ Ready for Linking │ Ready for Planning │ sonnet/medium`. Note for staff-reviewer: #114 models linking as its own state rather than the spec's `precedes ready_for_planning, planned`, so that how-to-test line reads differently against #114.

## Round 1 after 🔴 (backend-coder, 2026-10-23): blocked before fixing

staff-reviewer rejected #114 (round 1 of 2), and so did the Grok reviewers (`review-rejected`). At head `36c8f690` CI is green, and `packaging_spec` now expects `bin/ol-tee`, so that finding is fixed. These are still open: `web/app.rb` requires `newrelic_rpm` with no runtime dependency, `CONFINED_COMMANDS` grants `rg`/`git log|show|diff` with every flag, the 🔗→📋 guard, `Spec#linked?` accepts invalid values, `Linker` stays silent on `unchanged`, the cycle check covers the whole tree, and `Gemfile.lock` lists only darwin platforms.

No code changed and no review thread was answered. Each fix or rebuttal depends on `blocked.md` B2 (whether the spec or #114's 🔗 state wins) and B3 (this worktree is on #122's branch, so a fix here would land on the wrong PR).
