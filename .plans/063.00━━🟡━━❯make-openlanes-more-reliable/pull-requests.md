# Pull Requests

## backend-coder, round 1

- B1 done: `just bump <version>` → `bin/bump-version`; `spec/openlanes/release/bump_version_spec.rb` (real `bundle lock` against a temp copy) and `spec/openlanes/release/lockfile_version_spec.rb`. `bundle exec rspec spec/openlanes/release` → 6 examples, 0 failures. `bundle exec rubocop` → 850 files, no offenses.
- B2 blocked: see `blocked.md` B1. `spec/openlanes/support/lefthook_spec.rb` is written and fails (5 examples) until the `architecture` job is in `lefthook.yml`.
- `.openlanes.yml` gained `coverage:` (M15).
- Follow-up for the PR description: `lefthook.yml`'s `format`, `rubocop` and `rspec` jobs point at `frontend/` and `rails/`, which do not exist here, so only `gitleaks` runs today. Out of scope for this plan.

## Frontend F1, round 1

- `web/cypress/e2e/keyboard.cy.ts`: the model-picker example now waits, after each ArrowUp, on a retrying `cy.focused().should(...)` that focus moved to a different option before sending the next key. No `cy.document()` activeElement reads, no fixed waits, keyboard only.
- Integration proof, real demo servers from `bin/web-e2e`, nothing stubbed: the drawer opens by keyboard, the listbox reaches Opus 5.5, and after Enter `/api/board` reports `claude-opus-5-5` for `005.00/staff-reviewer` and the drawer reads "Model Opus 5.5".
- 10-run result: `bin/web-e2e` limited to `cypress/e2e/keyboard.cy.ts`. First batch of 10: 9 passed, 1 failed at ~1s with 0 passing (not reproduced, cause unknown, likely server startup). Second batch of 12 consecutive runs: 12 passed.
- Full `bin/web-e2e`: exit 0, 37 of 37 passing across 9 specs.
- Spec filtering used a throwaway copy of `bin/web-e2e`, since removed; no other file touched.
