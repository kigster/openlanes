# 005.00 Front-end units

Builder: `frontend-coder`. Terminal output only; there is no web work in this plan (spec, "Back end / front end"). Order and graph are in `plan.md`.

## F1 `openlanes review` command and the Needs-you line

- **Discipline:** front end (terminal presentation).
- **Owns:** `lib/openlanes/cli/review/review.rb` (new: `CLI::Review`, arguments `pr` and `label`, flag `-n` / `--dry-run`, help text listing the labels from `Plans::ReviewLabel::ALL`; calls `Vcs.review` and renders its `Review::Result`: from → to, CI verdict, refusal reason; non-zero exit on refusal); the `register "review", Review` line in `lib/openlanes/cli.rb`; `lib/openlanes/presentation/reporter.rb` (prints `waiting on you: PR #N` for each number in a plan's `waiting_on`); `spec/openlanes/cli/review_spec.rb`; `spec/openlanes/presentation/reporter_spec.rb`; the `review` row in `spec/openlanes/cli/help_spec.rb`.
- **Must not touch:** `lib/openlanes/vcs/**`, `lib/openlanes/plans/review_label.rb`, `lib/openlanes/engine/**`. No label name is typed here; every one is read from `ReviewLabel::ALL`.
- **Depends on:** B1, B3 (the `Vcs.review` result shape), B6 (the `waiting_on` field).
- **Done when:** `review_spec.rb`, with a `Vcs.review` double, shows the rendered transition, the refusal message and exit status while CI is red, the dry-run footer from `CLI::Base`, and an unknown label rejected with the valid list; `reporter_spec.rb` shows `waiting on you: PR #12` for a plan with `waiting_on: [12]` and nothing for an empty list; `help_spec.rb` lists `review`.
