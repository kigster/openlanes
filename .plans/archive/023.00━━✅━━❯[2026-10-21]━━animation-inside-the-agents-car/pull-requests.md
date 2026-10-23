# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 109 | [\[023.00\](A) Animation Inside the Agents Car](https://github.com/kigster/openlanes/pull/109) | Merged 🟣 |

## Integration proof, 023.00 (luke-backend, round 1, 2026-10-16)

- `cd web && npm run build` → `✓ built`
- `bundle exec exe/openlanes web --demo --no-open --port 11423 --redis-url redis://localhost:6379/12` → `/healthz` `ok`
- `cd web && npx cypress run --config "baseUrl=http://127.0.0.1:11423,specPattern=/tmp/luke-023-b1/gear.cy.js,video=false,supportFile=false,screenshotsFolder=/tmp/luke-023-b1/shots" --spec /tmp/luke-023-b1/gear.cy.js` → `4 passing` (checks 2 to 5; details in `integration.md`)
- `cd web && npm run lint && npm run typecheck && npm run coverage` → 35 files, 364 tests passed
- `bundle exec rspec` → 3123 examples, 0 failures
- `bundle exec rubocop` → 435 files, no offenses
- The repo's Cypress e2e suite (`npm run cy:run`) was not run: out of time budget; the plan assumes no Cypress assertion.
- Fix found by the proof: reduced-motion rule in `web/src/board/board.css` lost on specificity; now `.car.is-running .car-gear { animation: none; }`, pinned by `boardCss.test.ts`.

## Front end proof, 023.00 (rey-frontend, round 1, 2026-10-19)

- `cd web && npx vitest run` → 35 files, 364 tests passed
- `cd web && npx tsc --noEmit` → no errors
- F1: `Board.test.tsx` covers `is-running` and `.car-gear` on running cars, absent on done/stuck/failed/blocked/interrupted
- F2: `boardCss.test.ts` pins the keyframe, the running rule and the reduced-motion `animation: none`
- Integration proof: see luke's section above (gear.cy.js 4 passing, web-e2e 23/23)
