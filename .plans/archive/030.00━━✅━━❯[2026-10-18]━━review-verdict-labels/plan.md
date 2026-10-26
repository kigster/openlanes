# ✅ 030.00: Review Verdict Labels 

## Already on main before this plan

- `Plans::ReviewLabel::ALL` holds R3's seven labels and colours (5d4ba79, 795279b).
- `Vcs::LabelSync` creates and recolours them when a publishing run starts (3756ac3).
- `Plans::Verdict` counts the opening emoji; only `security-reviewer` counts 💣 and 🔓 (576d351).
- `review.max_hmm` (default 5), overridden by `$OPENLANES_REVIEW_MAX_HMM` (`Config#max_hmm`).

## Backend

### U1 Restart-safe migration of M3's `ready-to-merge`

- `Vcs::GitHub#open_pulls_labelled(name, repo:)`: `gh pr list --state open --label NAME --json number`.
- `Vcs::LabelMigration`: while the repo's `ready-to-merge` label has any colour but R3's `5319e7`, every open PR carrying it is swapped to `review-approved` (taking off every other verdict).
- The marker is the repo label's colour, not a local file: `LabelSync` recolours `ready-to-merge` only after the migration ran, so an interrupted migration leaves it M3's and the next start moves only what is left; once recoloured, the migration never runs again, so verifier's later `ready-to-merge` is left alone. A second machine agrees.
- `RunWorkflow#sync_labels` runs the migration, then the sync. A migration error skips the sync (warned), so the marker stays pending.
- Specs: `spec/openlanes/vcs/label_migration_spec.rb` (existing PRs, dry run, interrupted run, repeated startup, no label), `github_spec.rb`, `run_workflow_spec.rb` (order, failure skips sync).

Known limit: a repo whose `ready-to-merge` was already recoloured by an earlier openlanes release (3756ac3 shipped before this) counts as migrated; its old approvals cannot be told from verifier's.

## Frontend

None.

## Baseline

Before: the baseline run outran its 10-minute window, so no count; main was green per CLAUDE.md.
After: `bundle exec rspec`: 3558 examples, 0 failures, 9 pending, exit 0. `bundle exec rubocop`: no offenses.

## Task completed when

- Starting on a repo creates or recolours the labels.
- Comments with any ⛔️ or 💣 give `review-rejected` (plus `review-vulnerability` for 💣); more than five 🤔 (a setting, env-overridable) gives `review-ok-not-perfect`; otherwise `review-approved`.
- A restart-safe migration relabels open PRs carrying the old `ready-to-merge` to `review-approved` before the new meaning is enabled. Specs cover existing PRs, an interrupted migration, and repeated startup.
- Only security-reviewer's comments may count 💣 and 🔓.

## How to test

- Starting on a repo creates or recolours the labels.
- Comments with any ⛔️ or 💣 give `review-rejected` (plus `review-vulnerability` for 💣); more than five 🤔 (a setting, env-overridable) gives `review-ok-not-perfect`; otherwise `review-approved`.
- A restart-safe migration relabels open PRs carrying the old `ready-to-merge` to `review-approved` before the new meaning is enabled. Specs cover existing PRs, an interrupted migration, and repeated startup.
- Only security-reviewer's comments may count 💣 and 🔓.
