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

## Status

- [x] B1 `Plans::ReviewLabel`, docs table.
- [x] B2 `GitHub#ensure_label`, `#swap_label`, `#labels`, `#checks` (via `run!`: gh exits non-zero on a failing check), `#review_comments`, `.repo_of`; `labels:` on `#pulls`.
- [x] B3 `Vcs::CiGate`, `Vcs::Review`, `Vcs.review`; hansolo `may: [gh pr comment]`.
- [x] B4 `Spec#how_to_test`, `Spec::HOW_TO_TELL`, `Completion::HOW_TO_TEST` (`## How to test`).
- [x] B5 Publisher refuses without `## How to test`, copies it into the PR body, applies `ready-for-review`; `Publication#label_error`.
- [x] B6 `Engine::PrWatch` (read only: `due?` by elapsed time, `poll(subjects)`, one `gh pr list`), `Engine::PrOutcomes` (the effects), dispatcher wiring, `merge.by` in `support/config.rb`.
- [x] F1 `openlanes review`, `waiting on you: PR #N` in the reporter.
- [x] I1 `spec/integration/review_labels_spec.rb` with `spec/support/fake_gh/` (round 2, below).

## Status (round 2, salvage and finish)

B6 wiring and I1 were finished in round 2, after the round-1 work was committed as it stood.

- Dispatcher: `watch:` (a `PrWatch` or nil) reaches it through `Runner`. Each tick, `watch_pull_requests` starts the poll on a thread of its own when due and applies the finished outcomes on a later tick, so a slow `gh` never stretches the one-second tick. Plans with an agent running, being discarded or drained, or held by another machine are not watched that round.
- `Engine::PrOutcomes` (new, `lib/openlanes/engine/pr_outcomes.rb`) holds the effects, so the dispatcher hunk stays small: `review-rejected` → 🔴 plus mail; merged → the row says `Merged 🟣`, then ✅ once nothing is open; closed unmerged → the row says `Closed 🔴`, then `discarded.md` and ❌ once nothing is open or merged. Each step is asked of the folder as it stands, so a repeat poll does nothing.
- `publish_for_review` appends `ready-for-review not applied: <error>` to the attempt note when `Publication#label_error` is set.
- `waiting_on` is on `Board` and in the state file (`StateFile#waiting_on`); `Presentation.reporter` reads it only while the run that wrote it is alive (`StateFile#running?`).
- `openlanes run`/`start`: a staying run in human mode gets `PrWatch.new(github: Vcs.github)`; a dry run never does. A run that does not stay logs `not watching NNN.MM #N, ...` at the end (open question 1).
- `.openlanes.yml`: `merge: { by: human | auto }`, default `human` (`Config#merger`, `#human_merges?`).

### Amendments from round 1

amended: errors are `OpenLanes::Error`; there is no `Vcs::GitHub::Error` (`Error` inside `Vcs` resolves to `OpenLanes::Error`).
amended: `lib/openlanes.rb` gained `loader.collapse(".../cli/review")`, written by luke for the review command; without it the suite did not load.
amended: hansolo's executor example (`spec/openlanes/execution/executor_spec.rb`) now asserts `gh pr review` is denied.

### Decisions made in round 2

1. The rejection mail goes to every agent whose `handles:` includes 🔴, read from the full registry (not the run's roster), rather than to `luke-backend` and `rey-frontend` by name. Today that is luke, rey and r2d2. Naming them would be a second copy of `handles:`, and a run typed with `--agent` must not lose the mail, which waits in the plan folder for the next builder.
2. The mail is signed `github`, since a person wrote the comments, not an agent.
3. A person who rejects or merges on GitHub while the plan is still at 🟢 (before hansolo) moves it through 👀 first, the only state the machine rejects or approves from.
4. A merged or closed pull request is first recorded in `pull-requests.md` (wording from `PullRequests::STATES`), because ✅ and ❌ are judged by that file. This also stops the watch from asking about it again.
5. Closing every pull request unmerged discards the plan (❌), with `discarded.md` naming them. A plan with any other pull request merged or still open stays where it is.
6. `waiting_on` reaches `openlanes list-plans` through the state file, and only while the engine is up. Once the engine stops nobody is watching, and a pull request merged in the meantime would still show as waiting.
7. I1 drives the engine half through `Dispatcher#tick` with an injected clock and a roster of `leah-researcher`, who handles only ⚪️, so no agent starts. The publisher, `exe/openlanes review` and the watch all run real `gh` argv against the fake.

After B1 to B5 and PrWatch: `bundle exec rspec` 2281 examples, 0 failures; `bundle exec rubocop` 0 offenses.

After round 2: `bundle exec rspec` 2310 examples, 0 failures; `bundle exec rubocop` 0 offenses.
