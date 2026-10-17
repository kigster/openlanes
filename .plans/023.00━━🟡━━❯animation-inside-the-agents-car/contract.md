# Contract: 023.00 Animation Inside the Agents Car

Owner: `luke-backend`. Partner: `rey-frontend`.

## Baseline (before any change, 2026-10-16)

- `bundle exec rspec`: 3123 examples, 0 failures, 9 pending (seed 48018). No failing files.
- `bundle exec rubocop`: 435 files inspected, no offenses detected.
- Front end (from `spec.md` `## Research`): `cd web && npx vitest run`, 34 files, 355 tests, all passed.

## Interfaces rey calls

None. The plan adds and changes no HTTP route, payload field or Ruby method. The page keeps reading `Car.state` (`web/src/api/types.ts:32`), which the demo server already sends as `"running"` for working cars (`lib/openlanes/web/demo_board.rb:17`). No `openapi.yaml`.

The only "interface" between the halves is the DOM contract B1 checks:

| Selector / property                                   | Present when                                     | Value                    |
| :---------------------------------------------------- | :----------------------------------------------- | :----------------------- |
| `.car.is-running`                                     | `car.state === "running"` and not `look.blocked` | class on the card        |
| `.car.is-running .car-top > .car-gear` (first child)  | same                                             | inline SVG, `aria-hidden="true"` |
| computed `animation-name` of `.car-gear`              | running card, normal motion                      | `car-gear-spin`          |
| computed `animation-name` of `.car-gear`              | `prefers-reduced-motion: reduce`                 | `none`                   |
| `.car-gear` on done, stuck, failed, blocked, interrupted cards | never                                   | absent                   |

## File ownership

| Files                                                                 | Owner          |
| :-------------------------------------------------------------------- | :------------- |
| `web/src/board/Car.tsx`, `web/src/board/Gear.tsx`, `web/src/board/Board.test.tsx` | rey (F1) |
| `web/src/board/board.css`, `web/src/board/boardCss.test.ts`           | rey (F2)       |
| `contract.md`, `integration.md`, `pull-requests.md` (this plan folder) | luke (B1)     |

Shared files: none. Luke writes nothing under `web/`, `lib/` or `spec/`.

## Build order

1. F1 and F2, in parallel (rey).
1. B1 (luke), after rey mails that F1 and F2 are done.

## Integration proof

Nothing stubbed: the real Ruby server over the demo engine, serving the real built page, driven by a real browser.

1. `cd web && npm run build` (= `just web-build`).
1. `bundle exec exe/openlanes web --demo --no-open --port <free port>` (= `just web-demo`; port 11000 was taken by another session on this machine, so B1 uses a free one).
1. `curl /api/...` board payload holds a car with `state: "running"`; `spec/openlanes/web/demo_board_spec.rb` green.
1. A throwaway Cypress spec, kept outside the repo, visits the page and asserts the DOM table above, with reduced motion emulated through CDP `Emulation.setEmulatedMedia`.

Results go to `integration.md`.

## Baseline results

- Both commands exit 0. `spec/openlanes/web/demo_board_spec.rb`: 38 examples, 0 failures.

## Round 1 note (luke)

- Assumption: rey had not started on 023.00 during luke's round 1, so B1 ran only its red run (see `integration.md`). B1's green run is the last step of the plan and goes to whichever of us finishes last, per the integration proof above.
