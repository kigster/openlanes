# 005.00 Implementation plan (contract)

Owner: `luke-backend`. Partner: `rey-frontend`.

## Baseline

`bundle exec rspec` before any change: 2214 examples, 0 failures. `bundle exec rubocop`: 0 offenses.

## Interfaces rey calls

### `OpenLanes::Plans::ReviewLabel` (B1)

- `ReviewLabel = Data.define(:name, :colour, :meaning, :passing)`.
- `ReviewLabel::ALL`: the six M3 labels, in M3 order: `ready-for-review`, `review-in-progress`, `review-passed`, `ready-to-merge`, `review-rejected`, `ok-to-merge`.
- `ReviewLabel.names` -> `Array<String>`, the six names in that order.
- `ReviewLabel.fetch(name)` -> `ReviewLabel`; raises `OpenLanes::Error` with the valid list (`unknown review label "x"; one of: ready-for-review, ...`) on an unknown name.
- `ReviewLabel.passing` -> the three passing labels. `ReviewLabel::INITIAL` -> the `ready-for-review` entry.

### `OpenLanes::Vcs.review(github: Vcs.github)` -> `Vcs::Review` (B3)

- `#call(pr:, label:, dry_run: false)` -> `Review::Result`.
  - `pr`: `"12"`, `"#12"` or a PR URL. `label`: a label name (String).
  - raises `OpenLanes::Error` for an unknown label (before any `gh` call), and `Vcs::GitHub::Error` (an `OpenLanes::Error`) when `gh` fails.
- `Review::Result = Data.define(:pr, :from, :to, :ci, :refused, :reason, :dry_run)`:
  - `pr`: Integer PR number.
  - `from`: `Array<String>` review labels the PR carried before (usually 0 or 1).
  - `to`: String, the label asked for.
  - `ci`: `:green`, `:red`, `:pending` or `:none`.
  - `refused`: Boolean. When true nothing was written.
  - `reason`: String or nil. Refusal reasons: `"CI is red"`, `"CI pending"`. When `ci` is `:none` and not refused: `"no CI checks reported; treated as green"`.
  - `dry_run`: Boolean, echoed back.
- `Result#refused?` is an alias for `refused`.
- CLI exit status: non-zero when `refused?`.

### Board snapshot `waiting_on` (B6)

- Each plan entry in the board snapshot gains `waiting_on: Array<Integer>` (PR numbers open and awaiting a human), empty by default. Reporter reads it; nothing else to call.

## File ownership

- luke: everything in `plan-backend.md` (B1–B6, I1).
- rey: `lib/openlanes/cli/review/review.rb`, the `register "review"` line in `lib/openlanes/cli.rb`, `lib/openlanes/presentation/reporter.rb`, `spec/openlanes/cli/review_spec.rb`, `spec/openlanes/presentation/reporter_spec.rb`, `spec/openlanes/cli/help_spec.rb`.
- Shared: none. `documentation.rb` is luke's (B1).

## Build order

B1, B4 → B2 → B3, B5 → B6 → F1 → I1.

## Integration proof

`spec/integration/review_labels_spec.rb` (I1): real `.plans` tree, real `exe/openlanes review`, fake `gh` first on `PATH`.

## Status (luke-backend, round 1)

- [x] B1 `Plans::ReviewLabel`, docs table.
- [x] B2 `GitHub#ensure_label`, `#swap_label`, `#labels`, `#checks` (via `run!`: gh exits non-zero on a failing check), `#review_comments`, `.repo_of`; `labels:` on `#pulls`.
- [x] B3 `Vcs::CiGate`, `Vcs::Review`, `Vcs.review`; hansolo `may: [gh pr comment]`.
- [x] B4 `Spec#how_to_test`, `Spec::HOW_TO_TELL`, `Completion::HOW_TO_TEST` (`## How to test`).
- [x] B5 Publisher refuses without `## How to test`, copies it into the PR body, applies `ready-for-review`; `Publication#label_error`.
- [~] B6 `Engine::PrWatch` built and specced (`lib/openlanes/engine/pr_watch.rb`: `due?` by elapsed time, `poll(subjects)` -> `Outcome(plan:, pr:, kind:, comments:)`, kinds `:rejected/:merged/:closed/:waiting`). NOT done: the dispatcher wiring (fire 🔴/✅/❌, mail luke and rey, `label_error` in the attempt note, `waiting_on` in the board snapshot, `start`-only), and `merge.by` in `support/config.rb`.
- [ ] I1 integration spec: not started (depends on B6's wiring).

Next step (whoever resumes): wire `PrWatch` into `Dispatcher#tick` under `openlanes start` with `merge.by: human`; feed `waiting_on` into `Reporter.new(tree:, waiting_on: {"NNN.MM" => [n]})` as rey built it; then I1.

amended: errors are `OpenLanes::Error`; there is no `Vcs::GitHub::Error` (`Error` inside `Vcs` resolves to `OpenLanes::Error`).
amended: `lib/openlanes.rb` gained `loader.collapse(".../cli/review")`, written by luke for the review command; without it the suite did not load.
amended: hansolo's executor example (`spec/openlanes/execution/executor_spec.rb`) now asserts `gh pr review` is denied.

After B1 to B5 and PrWatch: `bundle exec rspec` 2281 examples, 0 failures; `bundle exec rubocop` 0 offenses.
