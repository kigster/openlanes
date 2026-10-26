# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 81 | [\[029.00\](A) Grill New Ideas Before the Spec](https://github.com/kigster/openlanes/pull/81) | Merged 🟣 |

## backend-coder, round 1: checks run before signing

- `bundle exec rspec`: 3560 examples, 0 failures, 9 pending (exit 0)
- `bundle exec rubocop`: 486 files inspected, no offenses detected
- `bundle exec rspec spec/openlanes/live spec/openlanes/web` (integration proof: `POST /api/interview` and `create_plans` with decisions): 675 examples, 0 failures
- `cd web && npx vitest run`: 35 files, 382 tests passed
- `cd web && npx tsc -b --noEmit` and `npx eslint src/panels`: clean
- No end-to-end (Cypress) run: needs a built page and a live server; not run this round.

## backend-coder, after staff-reviewer's rejection: checks run before signing

Finding fixed: `postInterview` had no test of its own. `web/src/api/client.test.ts` now covers the ok path (token, path, body), the no-interviewer reason, and the non-ok branch (422, 500).

- `cd web && npm run coverage && npm run coverage:changed`: `ok 100.0% 53/53 src/api/client.ts`, `ok 96.8% 61/63 src/panels/IdeaDialog.tsx` (385 tests passed)
- `cd web && npx tsc -b --noEmit && npx eslint src/api src/panels`: clean
- `bundle exec rspec`: 3560 examples, 0 failures, 9 pending (exit 0). One earlier run failed `spec/openlanes/apps/supervisor_spec.rb:59` on a port race (`refused 11102`); this branch does not touch `apps/`, and the file passed 3 of 3 runs alone.
- `bundle exec rubocop`: 486 files inspected, no offenses detected
