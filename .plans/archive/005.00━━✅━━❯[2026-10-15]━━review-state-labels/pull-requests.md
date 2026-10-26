# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 26 | [\[005.00\] Review State Labels](https://github.com/kigster/openlanes/pull/26) | Merged 🟣 |

## Verification

Run in the worktree `kig/005.00-review-state-labels`, rebased on `origin/main`, on 2026-10-14.

- `bundle exec rspec`: 2310 examples, 0 failures.
- `bundle exec rubocop`: 318 files, 0 offenses.
- `bundle exec rspec spec/integration/review_labels_spec.rb`: 2 examples, 0 failures.

(A list rather than a table: `pull-requests.md` is parsed for its first table, which must be the pull requests.)

What the end-to-end spec shows, with real git, a real `.plans` tree, the real `exe/openlanes` and a fake `gh` first on `PATH`:

- The publisher opens the PR with `ready-for-review` and records it in `pull-requests.md`.
- `openlanes review <n> review-in-progress` replaces it; exactly one review label remains.
- With a failing check, `openlanes review <n> ready-to-merge` exits non-zero saying "CI is red"; `review-rejected` is accepted.
- One watch poll 15 s later (injected clock) moves that plan to 🔴 with the comment mailed to backend-coder and frontend-coder, moves a merged plan to ✅, and reports `waiting on you: PR #42` for one still open.
- No `gh` call carries `--force`.
- A `plan.md` without `## How to test` makes the publisher refuse, and no PR is opened.

Not verified: any call against real GitHub (forks, tokens without label rights, how `action_required` maps to a bucket). The first live run is the real test (spec, Risks).

## Fix for staff-reviewer's finding 1 (round 1, 2026-10-15)

Cause: CircleCI job 335 (`ci/circleci: test`) ran rspec green, then failed its `Coverage of changed files` step: `coverage-changed: below 95%: lib/openlanes/engine/board.rb` (93.75%). The one line never run was the rescue in `Board::Row.unacked_in` (`board.rb:104`), so this was a real gate failure, not an environment problem.

Fix: `spec/openlanes/engine/board/row_spec.rb` gains "is 0 for a plan whose state.json is not valid JSON". It fails when the `OpenLanes::Error` rescue is removed. No `lib/` change.

Run in the worktree on 2026-10-15:

- `bundle exec rspec`: 2722 examples, 0 failures, 9 pending.
- `bundle exec rubocop`: 358 files, 0 offenses.
- `bin/coverage-changed --files <the 24 lib files PR #26 changed>`: all at or above 95%; `board.rb` 100.00%.

PR #26 was merged (e998e0d, 2026-10-15 15:40Z) before this fix existed. The branch `kig/005.00-review-state-labels` still accepts pushes, but nothing pushed to it reaches `main` now, so this commit has to go out on a new branch from `main` with its own PR. `board.rb` and `row_spec.rb` are identical on `main`, so the commit applies cleanly there.
