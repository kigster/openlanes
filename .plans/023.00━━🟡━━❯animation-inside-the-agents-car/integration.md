# Integration: 023.00 B1, the demo server drives a spinning gear

Owner: `luke-backend`. Status: **waiting on F1 and F2.** `rey-frontend` had not started on this plan during luke's round 1 (no signature in `state.json`, no process, no change under `web/`), so checks 3 to 5 have only been run against the code before the change, where they fail as they should.

## Setup (nothing stubbed)

- Build: `cd web && npm run build` (= `just web-build`). Built clean.
- Server: `bundle exec exe/openlanes web --demo --no-open --port 11423 --redis-url redis://localhost:6379/12` (= `just web-demo`). Port 11000 and Redis DB 0 were in use by another session's demo on this machine; a second demo on the same Redis would show up as another machine's tab.
- Browser check: a throwaway Cypress spec outside the repo, `/tmp/luke-023-b1/gear.cy.js`, run from `web/` with
  `npx cypress run --config "baseUrl=http://127.0.0.1:11423,specPattern=/tmp/luke-023-b1/gear.cy.js,video=false,supportFile=false,screenshotsFolder=/tmp/luke-023-b1/shots" --spec /tmp/luke-023-b1/gear.cy.js`.
  Reduced motion is emulated through CDP `Emulation.setEmulatedMedia` (`prefers-reduced-motion: reduce`).

Demo cars the check keys on (`GET /api/board`, `me.plans`):

| Car                       | state     | Blocked by       | Expect          |
| :------------------------ | :-------- | :--------------- | :-------------- |
| `001.00/rey-frontend`     | running   | nothing          | gear, spinning  |
| `005.00/hansolo-reviewer` | running   | nothing          | gear, spinning  |
| `001.00/luke-backend`     | stuck     | stuck + question | no gear         |
| `006.00/r2d2-mechanic`    | running   | open question    | no gear         |

The demo has no `done`, `failed` or interrupted car and no locked plan. Those cases are covered by F1's unit tests in `Board.test.tsx`; check 5 adds the lock span to each running `.car-top` in the page, with the markup `Car.tsx` renders, to measure the layout with it present.

## Results

Run 1, 2026-10-16, before F1 and F2 (the red run: proves each check can fail).

| # | Check                                                                                 | How                                                                                                      | Result |
| - | :------------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------- | :----- |
| 1 | `just web-build`, `just web-demo` serve the page                                      | commands above; `curl -sf http://127.0.0.1:11423/healthz`                                                 | pass   |
| 2 | Payload holds a running car; `demo_board_spec.rb` green                               | `curl -s http://127.0.0.1:11423/api/board \| jq` shows 3 running cars; `bundle exec rspec spec/openlanes/web/demo_board_spec.rb`: 38 examples, 0 failures | pass   |
| 3 | Running unblocked cards carry `.car.is-running` and `.car-top > .car-gear:first-child`, `animation-name: car-gear-spin`, infinite; the others have no `.car-gear` | Cypress `it("3: ...")`                                                    | fail (expected: no gear yet) |
| 4 | Reduced motion: gear visible, `animation-name: none`                                  | Cypress `it("4: ...")`                                                                                   | fail (expected: no gear yet) |
| 5 | Several running cars, `.car-top` stays one row with gear, name, lock mark and model   | Cypress `it("5: ...")`: 4 children, all inside the box, vertical centres within 4 px                     | fail (expected: no `.is-running` yet) |

## Next step

Once rey mails that F1 and F2 are done and `just web-test` is green: rebuild `web/dist`, restart the server, rerun the Cypress command above, and replace the table with run 2. If the `/tmp` spec is gone, recreate it from the five checks above.
