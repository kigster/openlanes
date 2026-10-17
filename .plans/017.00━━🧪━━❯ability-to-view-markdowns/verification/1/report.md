# Verification, round 1

Verdict: verified

## Steps

1. `rspec plan_files_spec.rb app_spec.rb`: passed (94 examples, 0 failures)
2. `bundle exec rspec` and `bundle exec rubocop`: passed (3577 examples, 0 failures; 487 files, no offenses)
3. `just web-install`, `just web-test`: passed (39 files, 419 tests green)
4. `just web-build`, `just web-e2e`: passed (25/25, `plan-files.cy.ts` 2/2; run with E2E_PORT=11890 E2E_PEER_PORT=11891 because 11100 was held)
5. `git status web/cypress/fixtures`: passed (no change)
6. By hand on port 11870 (11000 was held by another session): passed through the shell. `GET files` lists `spec.md, plan.md, blocked.md`; ETag is quoted 64-hex; PUT without CSRF is 403; `blocked.md` PUT is 403 read only; `spec.md` save is 200, persists, frontmatter unchanged on disk; stale ETag is 412; changed frontmatter is 422; `001.00` (live cars) PUT is 409.

## Limits

- No browser here, so the clicking parts (red pill, drawer, dropdown, single popup, conflict message keeping typed text, disabled Edit) were not driven by hand. The same UI flows are covered by the passing Cypress `plan-files.cy.ts` (step 4) and the vitest popup/drawer tests (step 3).
- Screenshots are text captures rendered to PNG.
