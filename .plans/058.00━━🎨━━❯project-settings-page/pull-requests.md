# Pull Requests

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
