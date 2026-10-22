# Pull Requests

## Checks, round 1 (luke-backend)

- `bundle exec rubocop`: 441 files inspected, no offenses detected
- `bundle exec rspec`: 3177 examples, 30 failures, 9 pending; all 30 in `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb` (machine answers every local port, see `blocked.md` B1)
- `bundle exec rspec spec/openlanes/{plans,evals,agents,engine,execution} spec/openlanes/vcs/mainline_spec.rb spec/openlanes/cli/link_spec.rb spec/openlanes/lifecycle/linker_spec.rb spec/openlanes/cli/help_spec.rb`: 1194 examples, 0 failures
- `./exe/openlanes agents list`: `ewoki-linker │ precedes ready_for_planning, planned │ in place`
- integration proof `spec/openlanes/cli/link_spec.rb`: `link --dry-run` prints `would invoke ewoki-linker for 050.00` and nothing for the `[none]` plan; refuses in a linked worktree and off `main`
- `./exe/openlanes evals ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS; `--recording fail` fails all three

## Checks, round 1 resumed after B1 (luke-backend, 2026-10-21)

B1 answered (b): the 30 `apps/` failures are accepted as outside this plan (plan.md D5). Re-run after the harness restart:

- `bundle exec rubocop`: 441 files inspected, no offenses detected
- `bundle exec rspec`: 3177 examples, 30 failures, 9 pending; filtering the failure list for anything outside `spec/openlanes/apps/` and `spec/openlanes/cli/app_spec.rb` prints nothing
- `./exe/openlanes agents list`: `ewoki-linker │ precedes ready_for_planning, planned │ in place │ haiku/low`
- `./exe/openlanes evals ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS
- `docs/badges/coverage_badge.svg` reverted; the suite rewrites it on every run

## Checks after the harness rebase onto `main` 667bcf0e (luke-backend, 2026-10-21)

Branch `kig/008.01-spec-ewoki-linker`, HEAD `338804aa Ewoki Linker`. The previous publish failed with `src refspec kig/008.01-ewoki-linker does not match any`: the harness pushed a branch name that differs from the worktree's branch.

- `bundle exec rubocop`: 565 files inspected, no offenses detected
- `bundle exec rspec`: 4213 examples, 0 failures, 9 pending (the B1 port failures no longer occur)
- `./exe/openlanes agents list`: `ewoki-linker │ precedes ready_for_planning, planned │ in place │ haiku/low`
- `./exe/openlanes evals ewoki-linker`: link-one 8/8, none 7/7, shared-files-only 7/7, all PASS
- integration proof `bundle exec rspec spec/openlanes/cli/link_spec.rb`: 3 examples, 0 failures

## Round 2 (luke-backend, 2026-10-21): the branch the publisher pushes

Round 1 ended Completed but the plan stayed at 🟡, because 🟢 needs an open pull request and the publish failed with `src refspec kig/008.01-ewoki-linker does not match any`. Cause: this worktree was reused and still had `kig/008.01-spec-ewoki-linker` checked out, the head of spec PR #29, already merged. `Worktree#branch_for` derives `kig/008.01-ewoki-linker`, which did not exist. A push to the merged branch would have landed nowhere.

- `git switch -c kig/008.01-ewoki-linker` at `338804aa` (HEAD's SHA unchanged). `kig/008.01-spec-ewoki-linker` is left as it was, locally and on `origin`.
- To undo: `git switch kig/008.01-spec-ewoki-linker && git branch -D kig/008.01-ewoki-linker`.
- Harness follow-up, not done here: `Worktree#checkout_for` reuses an existing directory without checking that its branch is `branch_for(feature)`.
- `bundle exec rubocop`: 565 files, no offenses. `bundle exec rspec`: exit 0, 4213 examples, 0 failures, 9 pending. `agents list`: `ewoki-linker │ precedes ready_for_planning, planned`. `evals ewoki-linker`: 3/3 PASS.
