# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 27 | [\[004.00\] Web Control Room](https://github.com/kigster/openlanes/pull/27) | Open 🟡 |

## Verification (close-out, 2026-10-14)

| Command | Result |
| --- | --- |
| `just lint` | 307 files, 0 offenses |
| `just test` | 2232 examples, 0 failures, 98.63% |
| `bundle exec rspec spec/integration` (repeated) | 9 examples, 0 failures: control room 4, restart 2, two checkouts 3 |
| `bin/coverage-changed --base origin/main` | no changed `lib/` files |
| `npx vitest run` (in `web/`) | 28 files, 298 tests, 0 failures |
| `npx eslint .`, `npx tsc -b --noEmit`, `npm run typecheck` | clean |
| `npm run coverage:changed` | `src/App.tsx` 99.2% |
| `npx cypress run` against `openlanes web --demo --port 11055` | 21 tests in 5 specs, all pass |
| `circleci config validate` | valid |

The round-1 note below (integration specs timing out, 20 rubocop offenses) no longer reproduced on the salvaged files.

## Front end (rey-frontend, round 1)

| Command (in `web/`) | Result |
| --- | --- |
| `npx vitest run --coverage` | 28 files, 298 tests, 0 failures |
| `npm run coverage:changed` | passes (no changed `web/src` files on committed HEAD; script unit-tested) |
| `npx eslint .` | 0 offenses |
| `npm run typecheck` | exit 0 |
| `npx cypress run` against `openlanes web --demo --port 11055` | all 5 specs pass: actions 5, board 6, chat 2, keyboard 5, needs-you 3 |

Not run by me: the Ruby `bundle exec rspec spec/integration` and `rubocop` offenses sit in luke's files (`spec/integration/control_room_spec.rb`, `spec/support/control_room_process.rb`): integration specs time out waiting for the process, 20 rubocop offenses in those two files.

### Findings fixed

- Tabbing past the header tabs focused the first machine's tab, which selected it and replaced the Board, so a keyboard user could never Tab to a car. Fix: `activationMode="manual"` in `web/src/App.tsx`; arrows still switch views. Test: `App.test.tsx` and `keyboard.cy.ts`.
