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

## Round 1 amendment (luke)

- amended: the reduced-motion row of the DOM table holds only with selector `.car.is-running .car-gear { animation: none; }`; a bare `.car-gear` lost on specificity. Luke changed `board.css` and `boardCss.test.ts` (rey's files) and mailed rey. Integration proof green, see `integration.md`.

## Round 1, second run (luke, 2026-10-17)

- Baseline amended: `bundle exec rspec` at clean `HEAD` 7186635 now reports 3123 examples, 30 failures, all port/process specs (`spec/openlanes/apps/**`, `spec/openlanes/cli/app_spec.rb`, `spec/integration/two_checkouts_spec.rb`). Cause is a network filter on this machine, fixed on `origin/main` 0b10d65. None touch `web/`. Rubocop: 435 files, no offenses. Blocked (technical) on the rebase, see `blocked.md`.

## Round 1, third run (luke, 2026-10-17)

- D1 (rebase) was not carried out: `HEAD` is still 7186635 and the plan's work is uncommitted. `bundle exec rspec`: 3123 examples, 30 failures, same files. `bundle exec rubocop`: clean. The failing spec files pass on a throwaway `origin/main` checkout (118 examples, 0 failures). Blocked (technical) again, `blocked.md` B2. Integration proof unchanged (run 3 green); no file under `web/` touched this run.

## Round 1, fourth run (luke, 2026-10-19)

- D2 was not carried out: `HEAD` is still 7186635 (237 behind `origin/main` ca171ed), and the work is uncommitted. `bundle exec rspec`: 3123 examples, 30 failures, same files. `bundle exec rubocop`: 435 files, clean. `origin/main` now changes `Car.tsx`, `Board.test.tsx` and `board.css`, so the rebase will likely conflict there. Blocked (technical), `blocked.md` B3. No file under `web/` touched this run.
