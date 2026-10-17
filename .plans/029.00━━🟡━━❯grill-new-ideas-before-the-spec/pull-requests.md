# Pull Requests

## luke-backend, round 1: checks run before signing

- `bundle exec rspec`: 3560 examples, 0 failures, 9 pending (exit 0)
- `bundle exec rubocop`: 486 files inspected, no offenses detected
- `bundle exec rspec spec/openlanes/live spec/openlanes/web` (integration proof: `POST /api/interview` and `create_plans` with decisions): 675 examples, 0 failures
- `cd web && npx vitest run`: 35 files, 382 tests passed
- `cd web && npx tsc -b --noEmit` and `npx eslint src/panels`: clean
- No end-to-end (Cypress) run: needs a built page and a live server; not run this round.
