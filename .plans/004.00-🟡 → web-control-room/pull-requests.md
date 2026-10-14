# Pull Requests

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
