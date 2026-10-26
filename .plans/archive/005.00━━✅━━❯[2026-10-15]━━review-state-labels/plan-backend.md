# 005.00 Back-end units

Builder: `backend-coder`. Order and graph are in `plan.md`. File paths are relative to the repository root.

## B1 Review label vocabulary and its docs table

- **Discipline:** back end.
- **Owns:** `lib/openlanes/plans/review_label.rb` (new: `Plans::ReviewLabel = Data.define(:name, :colour, :meaning, :passing)`, constant `ReviewLabel::ALL` with the six M3 labels, `ReviewLabel.fetch(name)`, `ReviewLabel.passing`, `ReviewLabel::INITIAL` = `ready-for-review`); `lib/openlanes/presentation/documentation.rb` (label table rendered from `ReviewLabel::ALL`); `spec/openlanes/plans/review_label_spec.rb`; `spec/openlanes/presentation/documentation_spec.rb`.
- **Must not touch:** `lib/openlanes/plans/pull_requests.rb` (its `STATES` stays as it is, spec non-goal), every file owned by B2–B6, F1.
- **Depends on:** nothing.
- **Done when:** `review_label_spec.rb` asserts the six names and colours equal M3 (`docs/decisions/decisions-on-merge-modes-and-verification.md:27-34`) and that exactly `review-passed`, `ready-to-merge`, `ok-to-merge` are passing; `documentation_spec.rb` asserts `openlanes docs` output carries one row per `ReviewLabel::ALL` entry; `rg -F` for each label name finds the literal only in `review_label.rb` under `lib/`.

## B2 GitHub seam: labels, checks, comments

- **Discipline:** back end.
- **Owns:** `lib/openlanes/vcs/github.rb`; `spec/openlanes/vcs/github_spec.rb`.
- **Must not touch:** `lib/openlanes/execution/executor.rb` (`gh pr edit` stays in `FORBIDDEN_COMMANDS`), files of other units.
- **Depends on:** B1.
- **New methods** (each runs `gh` with `-R owner/repo` taken from the PR URL; a `TTY::Command::ExitError` becomes `GitHub::Error` with the first stderr line, as `retitle` does):
  - `ensure_label(label, repo:)`: `gh label create <name> --color <hex> --description <meaning>`, never `--force`; "already exists" is success and the colour is left alone.
  - `swap_label(number:, repo:, add:, remove: [])`: ensures `add`, then one `gh pr edit <n> --add-label <add> --remove-label <each>`; returns the label set left on the PR. A failed remove of a label the PR lacks is tolerated (spec open question 6).
  - `checks(number:, repo:)`: `gh pr checks <n> --json name,state,bucket`, returns `[{name:, bucket:}]`.
  - `review_comments(number:, repo:)`: `gh pr view <n> --json comments,reviews`, returns bodies with author and URL.
  - `pulls` rows gain `labels:` (array of names) and keep `state:` from `state_label` (merged vs closed distinguishable).
- **Done when:** `github_spec.rb`, with a `TTY::Command` double, covers create-when-missing, left-alone-when-present (no `--force` in argv), swap argv with `-R`, tolerated failed remove, error surfacing with the first stderr line, `checks` parsing, `review_comments` parsing, and `labels:` on `pulls`.

## B3 Review verdicts: the CI gate, `Vcs::Review`, staff-reviewer

- **Discipline:** back end.
- **Owns:** `lib/openlanes/vcs/review.rb` (new: `Vcs::Review` with `call(pr:, label:, dry_run:)` returning `Review::Result = Data.define(:pr, :from, :to, :ci, :refused, :reason, :dry_run)`); `Vcs::CiGate` inside the same file or `lib/openlanes/vcs/ci_gate.rb` (new: `CiGate.verdict(checks) -> :green | :red | :pending | :none`); `Vcs.review` facade method in `lib/openlanes/vcs.rb`; `agents/staff-reviewer.md`; `spec/openlanes/vcs/review_spec.rb`; `spec/openlanes/vcs/ci_gate_spec.rb`; the staff-reviewer assertion in `spec/openlanes/agents/registry_spec.rb`.
- **Must not touch:** `lib/openlanes/cli/**` (F1 owns the command), `lib/openlanes/vcs/github.rb` (B2), `executor.rb`.
- **Depends on:** B1, B2.
- **Rules it encodes:** red = any bucket `fail`, `cancel` or an unknown bucket (open question 5); `skipping` neutral; any `pending` → `:pending`, and a passing verdict waits (returns refused with reason "CI pending", L5); zero checks → `:none`, treated as green with a warning in `reason` (open question 2). While `:red` only `review-rejected` is accepted. Replace-not-add: the swap removes every other `ReviewLabel::ALL` name the PR carries. Dry run computes the result and calls nothing that writes.
- **staff-reviewer:** `may:` drops `gh pr review` and keeps `gh pr comment`; the body tells it to run `openlanes review <pr> review-in-progress` at start and its verdict label at the end.
- **Done when:** `ci_gate_spec.rb` covers pass, fail, cancel, pending, skipping, unknown bucket and zero checks; `review_spec.rb` (with a `GitHub` double) shows exactly one review label left after each transition, refusal of every passing label while red, acceptance of `review-rejected` while red, and no write calls under dry run; `registry_spec.rb` asserts staff-reviewer's `may:` is `[gh pr comment]` and that `gh pr edit` is still in `Executor::FORBIDDEN_COMMANDS`.

## B4 How to test: spec section to plan.md

- **Discipline:** back end.
- **Owns:** `lib/openlanes/plans/spec.rb`; `lib/openlanes/lifecycle/completion.rb`; `lib/openlanes/execution/prompt.rb` (its `how-to-verify` read); `spec/openlanes/plans/spec_spec.rb`; `spec/openlanes/lifecycle/completion_spec.rb`; `spec/openlanes/execution/prompt_spec.rb`.
- **Must not touch:** `lib/openlanes/vcs/publisher.rb` (B5), `lib/openlanes/plans/status.rb` (the 📋 invariant from M10 belongs to plan 007).
- **Depends on:** nothing.
- **Shape:** `Plans::Spec#how_to_test` reads the `## How to tell it's working?` section, falling back to the `how-to-verify:` key until plan 007 lands (open question 3; the heading wins when both exist). `Completion` writes it under `## How to test` in `plan.md` instead of `## How to verify`. One constant names each heading (`Spec::HOW_TO_TELL`, `Completion::HOW_TO_TEST`) so the publisher reads it rather than retyping it.
- **Done when:** `spec_spec.rb` covers heading only, key only, both (heading wins), neither; `completion_spec.rb` asserts `## How to test` lands in `plan.md` and `## How to verify` no longer does; `prompt_spec.rb` stays green on the new reader.

## B5 Publisher: `ready-for-review` and the How-to-test gate

- **Discipline:** back end.
- **Owns:** `lib/openlanes/vcs/publisher.rb`; `spec/openlanes/vcs/publisher_spec.rb`; `spec/openlanes/vcs/publisher_carry_spec.rb` (only if its fixtures need a `## How to test`).
- **Must not touch:** `lib/openlanes/engine/dispatcher.rb` (B6 records the note), `github.rb`.
- **Depends on:** B1, B2, B4.
- **Shape:** before opening, refuse when `plan.md` has no `Completion::HOW_TO_TEST` section, through the existing refusal path; copy that section into the PR body. After opening, `swap_label(add: ReviewLabel::INITIAL)`; a `GitHub::Error` there does not undo the PR and is returned as `label_error:` on the publish result (open question 4).
- **Done when:** `publisher_spec.rb` shows a refusal without `## How to test`, the section in the PR body, `ready-for-review` applied on open, and a failing label double still yielding an open PR with `label_error` set.

## B6 Human-mode poll in the engine

- **Discipline:** back end.
- **Owns:** `lib/openlanes/engine/pr_watch.rb` (new: `Engine::PrWatch.new(github:, clock:, interval: 15)` with `due?`, `poll(subjects) -> [Outcome]`, `Outcome = Data.define(:plan, :pr, :kind, :comments)`, kinds `:rejected`, `:merged`, `:closed`, `:waiting`); `lib/openlanes/engine/dispatcher.rb` (call the watch from `tick` by elapsed time, not tick count; run the `gh` call off the tick thread and apply finished outcomes on a later tick; fire the 🔴 / ✅ / ❌ events through `StateMachine`; mail rejection comments to `backend-coder` and `frontend-coder` through the mailbox; record B5's `label_error` in the attempt note in `publish_for_review`; expose `waiting_on: [pr numbers]` per plan in the board snapshot); `lib/openlanes/support/config.rb` (read `merge.by`, default `human`); `spec/openlanes/engine/pr_watch_spec.rb`; `spec/openlanes/engine/dispatcher_spec.rb`.
- **Must not touch:** `lib/openlanes/presentation/**` (F1 renders `waiting_on`), `github.rb`, `publisher.rb`.
- **Depends on:** B2, B5.
- **Scope rule:** the watch runs only in a staying run (`openlanes start`), and only when `merge.by` is `human`. Plain `openlanes run` exits at its fixed point and logs the unpolled PR numbers (open question 1).
- **Done when:** `pr_watch_spec.rb`, with an injected clock and `GitHub` double, shows no call before 15 s and one `pulls` call after, and each outcome kind; `dispatcher_spec.rb` shows `review-rejected` plus comments → 🔴 with mail to backend-coder and frontend-coder, merged → ✅, closed unmerged → ❌, a label failure in the attempt note, `waiting_on` in the snapshot, and no polling under plain `run`.

## I1 Integration check: a PR through its labels, end to end

- **Discipline:** back end.
- **Owns:** `spec/integration/review_labels_spec.rb`; `spec/support/fake_gh` (a fake `gh` executable put first on `PATH`, recording argv to a file and answering from fixtures).
- **Must not touch:** any `lib/` file. A failure here is fixed in the owning unit.
- **Depends on:** B3, B5, B6, F1.
- **Done when:** the spec, on a real `.plans` tree from `PlansFixture` and nothing stubbed inside the process, shows in order: the publisher opens a PR and `ready-for-review` is applied; `exe/openlanes review <n> review-in-progress` replaces it; `exe/openlanes review <n> ready-to-merge` is refused while the fake reports a `fail` check, and `review-rejected` is accepted; a dispatcher tick 15 s later (injected clock) sees `review-rejected` with a comment, moves the folder to 🔴 and leaves mail for backend-coder and frontend-coder; a merged fixture moves another plan to ✅; the reporter prints `waiting on you: PR #N` for a still-open one. The recorded argv never contains `--force`.
