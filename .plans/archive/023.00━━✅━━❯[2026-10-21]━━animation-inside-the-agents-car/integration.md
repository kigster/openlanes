# Integration: 023.00 B1, the demo server drives a spinning gear

Owner: `backend-coder`. Status: **all five pass (run 3).** Run 1 was the red run before F1/F2. Run 2 found a real defect in the reduced-motion rule, fixed by backend-coder in `board.css` (see below). Run 3 is green.

## Setup (nothing stubbed)

- Build: `cd web && npm run build` (= `just web-build`). Built clean.
- Server: `bundle exec exe/openlanes web --demo --no-open --port 11423 --redis-url redis://localhost:6379/12` (= `just web-demo`). Port 11000 and Redis DB 0 were in use by another session's demo on this machine; a second demo on the same Redis would show up as another machine's tab.
- Browser check: a throwaway Cypress spec outside the repo, `/tmp/backend-coder-023-b1/gear.cy.js`, run from `web/` with
  `npx cypress run --config "baseUrl=http://127.0.0.1:11423,specPattern=/tmp/backend-coder-023-b1/gear.cy.js,video=false,supportFile=false,screenshotsFolder=/tmp/backend-coder-023-b1/shots" --spec /tmp/backend-coder-023-b1/gear.cy.js`.
  Reduced motion: CDP `Emulation.setEmulatedMedia` does not reach Cypress's AUT iframe (`matchMedia` stayed `false` in Electron and Chrome), so check 4 takes the served CSS's own `@media (prefers-reduced-motion: reduce)` rules from `document.styleSheets` and appends them unconditionally at the end of the document. That is what the browser does when the query matches: same selectors, same specificity, later in source order.

Demo cars the check keys on (`GET /api/board`, `me.plans`):

| Car                       | state     | Blocked by       | Expect          |
| :------------------------ | :-------- | :--------------- | :-------------- |
| `001.00/frontend-coder`     | running   | nothing          | gear, spinning  |
| `005.00/staff-reviewer` | running   | nothing          | gear, spinning  |
| `001.00/backend-coder`     | stuck     | stuck + question | no gear         |
| `006.00/chores-coder`    | running   | open question    | no gear         |

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

Run 2, 2026-10-16, after F1 and F2: checks 1, 2, 3 and 5 pass; **check 4 fails**: under the lifted reduced-motion rules both running gears still report `animation-name: car-gear-spin`. Cause: the override was `.car-gear { animation: none; }` (specificity 0,1,0), which loses to `.car.is-running .car-gear` (0,3,0). `boardCss.test.ts` only matched text, so it passed.

Fix (backend-coder, mailed to frontend-coder): `board.css` reduced-motion block now reads `.car.is-running .car-gear { animation: none; }`; `boardCss.test.ts` now requires that selector, so a bare `.car-gear` fails it.

Run 3, 2026-10-16, after the fix and `npm run build`:

| # | Check | How | Result |
| - | :---- | :-- | :----- |
| 1 | Build and demo serve the page | `npm run build`; `exe/openlanes web --demo` on 11423; `curl /healthz` = `ok` | pass |
| 2 | Payload holds a running car; `demo_board_spec.rb` green | `/api/board`: `001.00/frontend-coder`, `005.00/staff-reviewer`, `006.00/chores-coder` running; full `bundle exec rspec` 3123 examples, 0 failures | pass |
| 3 | Running unblocked cards: `.car.is-running`, first-child `.car-gear`, `aria-hidden`, `car-gear-spin`, `infinite`; stuck and question-blocked cards have no gear | Cypress `it("3")`: both running cars `animation-name=car-gear-spin iteration=infinite` | pass |
| 4 | Reduced motion: gear visible, `animation-name: none` | Cypress `it("4")`: both gears `animation-name=none` | pass |
| 5 | `.car-top` one row with gear, name, lock mark, model | Cypress `it("5")`: 4 children, inside the box, one centre row (h=22 and h=40.6, the latter wraps the model picker but centres agree) | pass |

Done, failed and interrupted cars are absent from the demo; F1's unit tests cover them.

Observed, not fixed (out of scope, Ruby demo): `POST /api/demo/reset` can race the demo's tick thread, which dies on Redis `NOGROUP ... XREADGROUP` (`lib/openlanes/web/demo.rb:138`), after which `/api/board` returns `me: null` until the server restarts. Hit once in five runs.
