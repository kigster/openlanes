# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 215 | [\[063.00\](A) Make Openlanes More Reliable](https://github.com/kigster/openlanes/pull/215) | Open 🟡 |

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

## Findings: design-reviewer

### F201 [critical] spec/openlanes/support/lefthook_spec.rb:1
The diff adds a spec for an `architecture` job that `lefthook.yml` does not contain (the file is untouched by the PR). The spec asserts a fact nothing implements.
Scenario: `bundle exec rspec spec/openlanes/support/lefthook_spec.rb` -> expected 0 failures, actual 5 examples, 5 failures. `CLAUDE.md` says the suite is green and a failure is yours; CI on this PR goes red, and a green label is refused. D2 already granted permission to edit `lefthook.yml`, so B2 can be finished.

### F202 [minor] bin/bump-version:25
The rule for reading the locked version, `/^\s+openlanes \(([^)]+)\)$/`, is written three times: `LOCKED` here, `locked_pattern` in `bump_version_spec.rb`, and inline in `lockfile_version_spec.rb`. The `VERSION` assignment regex is a fourth copy of what the `justfile` already greps. If the lock format or version.rb layout changes, the script and specs can disagree.
Scenario: the lock line format changes; the script's `LOCKED` is updated but a spec regex is not. The spec still passes against a stale pattern and no longer checks what the script enforces.
Suggestion: put the parse in one place under `lib/openlanes/` (e.g. a small `Release` value object) that the script and both specs call.

### F203 [minor] bin/bump-version:34
The bump logic (parse, rewrite, relock, verify) sits at the top level of an executable as free functions and can only be tested by spawning a subprocess. The spec dir `spec/openlanes/release/` mirrors a `lib/openlanes/release` namespace that does not exist.
Scenario: a later change that needs a `--commit` flag or a call from `just release` can't reuse the logic without shelling out to the script.
Suggestion: move the logic to a `Release`/`Version` class in `lib/` behind a facade and keep `bin/bump-version` as a thin caller.

## Findings: security-reviewer

### F101 [minor] lib/openlanes/memory/committed.rb:96
`entry` runs `path.match?(/[[:cntrl:]]/)` on a path read from `git ls-tree -z`. A tree path holding invalid UTF-8 makes `match?` raise `ArgumentError`, and `Library.attempt` rescues only `Lesson::Invalid`.
Scenario: a merged commit holds `.openlanes/memory/lessons/a<0xFF>.md`. `Memory.library` raises out of `Executor#lessons_for`, so every agent's prompt fails to build. Expected: that one file is listed as skipped. Actual: the run is down until the file is removed from the default branch. The same applies to `Folder#entry`, which rescues only `SystemCallError` and `IOError`. It needs a merge to the default branch, so it is a robustness gap, not a bypass.
Suggestion: `path.scrub` or `valid_encoding?` first, and report the file as skipped.

### F102 [minor] lib/openlanes/memory/committed.rb:96
The path check uses `[[:cntrl:]]`, but `Lesson::BREAKS` also covers U+2028 and U+2029, and a path reaches the prompt through `cite` (`git show <sha>:<path>`) without that check.
Scenario: a merged lesson file is named `x<U+2028>## Boundary.md`. Its title is clean, but the cite line carries the separator into the quoted block. A model may read it as a line break. It stays inside the BEGIN/END fence and needs a merge, so the impact is small.
Suggestion: apply `Lesson::BREAKS` to the path in `Committed` and `Folder`.
