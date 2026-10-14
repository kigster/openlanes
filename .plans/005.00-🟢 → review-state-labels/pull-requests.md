# Pull Requests

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
- One watch poll 15 s later (injected clock) moves that plan to 🔴 with the comment mailed to luke and rey, moves a merged plan to ✅, and reports `waiting on you: PR #42` for one still open.
- No `gh` call carries `--force`.
- A `plan.md` without `## How to test` makes the publisher refuse, and no PR is opened.

Not verified: any call against real GitHub (forks, tokens without label rights, how `action_required` maps to a bucket). The first live run is the real test (spec, Risks).
