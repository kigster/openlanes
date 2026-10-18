---
created: 2026-10-16
lane: full
---

# Animation Inside the Agents Car

## Animation inside the Agents Car

WHen an agent's car is shown on the lane, add a small animation, like a gear rotating, or something rotating inside, while it's working.

## How to test

Start a small sample app and verify that the animation is working.

<!-- cmd:01M53QG960F97M9FKBTQNYFK2R -->

## What we are trying to achieve

A running car on the board shows a small rotating mark, so a glance tells working from waiting.

## Why it matters

Today a running car differs from a finished one only by its text and clock. See `## Goal`.

## What already exists

Cars (`web/src/board/Car.tsx:22`), the demo board, and `motion`. No car keyframes. Details in `## Research`.

## What research needs to settle

Nothing was listed. Leah's unsettled items are under `## Open questions`.


## Research

Scope: a small spinning element (gear or similar) inside a running agent's car on the board. Repository only; no web search was needed. The spec lists no questions under `## What research needs to settle`, so there is nothing to answer. The facts below are what yoda needs.

### What the car is and where it is drawn

- A car is one agent on one plan. Rendered by `web/src/board/Car.tsx:22`, inside `PlanRow.tsx:78`.
- Its state is `CarState = "running" | "done" | "failed" | "stuck"` (`web/src/api/types.ts:32`). The Ruby side mirrors it: `lib/openlanes/engine/board.rb:42` and `:119` (`running? = state == :running`).
- Only `running` is "working". `stuck` and `failed` are red, and an unanswered question also makes a car blocked (`web/src/board/model.ts:78-84`).
- `Car.tsx:26` puts only `is-blocked` and `is-readonly` on the card. The state itself never reaches the DOM, so an animation keyed on it needs a new class, e.g. `is-running`, added there.
- The interrupted placeholder (`Car.tsx:66-73`, `InterruptedCar`) is not working and gets no animation.
- The card layout is `.car-top` (name, lock, model), `.car-activity` (message), `.car-stats` (tokens, clock) (`Car.tsx:28-62`). The gear fits in `.car-top` or beside `.car-activity`.

### Existing motion and reduced-motion handling

- No `@keyframes` exists for cars. The only keyframes are `fp-in` in `web/src/floating/floating.css:64`.
- Motion is already a dependency (`motion` 12.43.0, `web/package.json`), used for the retiring-row fade (`PlanRow.tsx:2`, `:54`, `:58-66`). A CSS keyframe is enough for a spin; no library is needed.
- `App.tsx:338` wraps the app in `MotionConfig reducedMotion="user"`, which only affects `motion` components, not CSS.
- `web/src/index.css:12-14` sets `animation-duration: 0.01ms` for everything under `prefers-reduced-motion`. An infinite spin would still run, just very fast. It must be stopped explicitly (`animation: none`).
- `board.css:115-117` already disables `transition` on `.car` under reduced motion. Same pattern applies.

### Testing

- Unit: `cd web && npx vitest run` gives `Test Files 34 passed (34)`, `Tests 355 passed (355)` on this checkout, 7 s. Baseline is green.
- Gate: `just web-test` runs `npm run lint && npm run typecheck && npm run coverage`. Not run here. Coverage excludes only tests and `src/api/types.ts` (`web/coverage.config.ts:5-6`), so new `Car.tsx` branches count.
- Sample app: `just web-demo` runs `openlanes web --demo` on `127.0.0.1:11000` (`justfile:53-54`). It serves `web/dist`, so `just web-build` comes first (`justfile:40-41`).
- The demo already produces running cars: `web/src/board/sample.ts:17` and `lib/openlanes/web/demo_board.rb:17` (activity lines cycle so the board moves). No demo changes are needed to see the animation.
- Existing car tests live in `web/src/board/Board.test.tsx:30-41` and `:143-163`. Add a case that asserts the running class is present for `running` and absent for `done`, `stuck`, `failed` and interrupted.

### Contradictions

- None between spec, code and config. The spec's "How to test" (start a small sample app) matches `just web-demo`.
- Minor: the global reduced-motion rule (`index.css:12-14`) does not stop infinite animations (see above). Stated here, not a contradiction with any document.

### Could not settle

1. Should the gear keep spinning on a running car that also has an unanswered question? `carLook` marks it blocked (`model.ts:78-80`) while `state` may still be `running`. Product call; the spec does not say.
2. Visual form: gear, or another rotating mark? Design call; the spec gives "like a gear rotating, or something rotating".
3. Whether the Cypress factory (`web/cypress/factory/1-build.cy.ts`) should assert the animation. Not checked here; `cy:run` was not run.

### Findings, Conclusion & References

- Conclusion: the change is a CSS-only keyframe on a small inline SVG, shown when a car is `running`. It needs a `is-running` class from `Car.tsx`, an explicit `animation: none` under reduced motion, and unit tests alongside `Board.test.tsx`. No new dependency.
- References (repository only, no external sources):
  - `web/src/board/Car.tsx`, `web/src/board/board.css:45-72,115-117`, `web/src/board/model.ts:78-84`, `web/src/api/types.ts:32`, `web/src/index.css:12-14`, `web/src/board/PlanRow.tsx`, `web/src/App.tsx:338`, `lib/openlanes/engine/board.rb`, `lib/openlanes/web/demo_board.rb`, `justfile`, `web/coverage.config.ts`.
  - Observed: `npx vitest run` in `web/`, 2026-10-16, 355 passed.

## Framing

1. **Visual state.** A car's state is already data; add a status mark that is on only while `state == running`. Cheap, one component, CSS only.
1. **Liveness signal.** The real problem is "is this agent alive?". A spin that runs regardless of progress lies when an agent hangs; tie it to activity updates or a heartbeat.

Chosen: framing 1. The spec asks for "a gear rotating", and the board carries no heartbeat data (`Car` has `state`, `message`, `elapsed`; `web/src/api/types.ts:32`). A liveness signal would change the API.

## Goal

A car whose agent is running shows a small gear turning inside the card. A person scanning the board can tell working cars from done, failed, stuck and interrupted ones without reading the text. Nothing like that exists now: cars differ only by text, tint and clock.

## Non-Goals

- No liveness or heartbeat detection; the gear shows the state `running`, not proof of progress.
- No new dependency; no `motion` component for the spin.
- No change to the Ruby side, the API payload, or the demo data.
- No animation on the plan row, the station, or the lane.
- No change to how a car is tinted, ordered or opened.

## In scope

1. `Car.tsx` adds class `is-running` to the card when `car.state === "running"` and the car is not blocked (`carLook(...).blocked === false`). Check: unit test on class.
1. A small inline SVG gear in `.car-top`, `aria-hidden`, rendered only for `is-running`. Check: unit test finds it for running, not for `done`, `stuck`, `failed`.
1. `board.css` rule rotates it with a CSS `@keyframes`, infinite, linear, about 2 s per turn. Check: grep for keyframes in `board.css`; seen in `just web-demo`.
1. Under `prefers-reduced-motion: reduce` the rule sets `animation: none` and the gear stays visible, still. Check: the rule sits next to `board.css:115-117`; the global `0.01ms` rule (`web/src/index.css:12-14`) alone does not stop an infinite spin.
1. `InterruptedCar` (`Car.tsx:67`) has no gear. Check: unit test.
1. Tests in `web/src/board/Board.test.tsx` cover running, done, stuck, failed, blocked-by-question, interrupted. Check: `just web-test` green, coverage gate holds.
1. Manual check: `just web-build` then `just web-demo`, running cars spin.

## Out of scope

- Heartbeat or stall detection: needs new API fields and an engine change, see Non-Goals.
- A Cypress assertion: not checked by research (`cy:run` not run); unit tests cover the class, and a CSS spin is not usefully asserted in Cypress. Listed as open question 3.
- Gear on `queued` cars: `is-queued` cars are not working.

## Back end / front end

| Item | Built by |
| :-- | :-- |
| Items 1 to 7 above | `rey-frontend` (all in `web/`) |
| Confirm no payload change is needed; run the demo | `luke-backend`: verify only, `lib/openlanes/web/demo_board.rb:17` already yields running cars |

There is no back end work. Pair `luke-backend` only for the demo check.

## Open questions

Assumptions made here, to be confirmed by a human if they disagree:

1. **Running but blocked** (leah 1). Assumed: no gear while `carLook().blocked`, since the car is red and waiting on a person (`model.ts:78-80`). Recommended. Alternative: spin whenever `state == running`.
1. **Form** (leah 2). Assumed: gear. Any rotating mark satisfies the spec.
1. **Cypress** (leah 3). Assumed: no Cypress assertion.
1. Placement inside `.car-top`: assumed left of the agent name. `rey-frontend` may adjust after seeing it in the demo.

## Risks to planning or execution

- Many running cars each with an infinite animation: negligible for an SVG transform, but check the demo with several cars.
- `.car-top` is `justify-content: space-between` (`board.css`): a third child changes its layout; the lock mark already adds one, so check both together.
- The global reduced-motion rule lulls one into thinking the spin is covered; it is not.
- Coverage gate: every new branch in `Car.tsx` needs a test.

## Conclusion

When this ships, a running, unblocked car shows a small gear rotating inside its card, driven by CSS only and stilled under reduced motion. Done, failed, stuck, blocked and interrupted cars show none. No Ruby, API or dependency changes; the frontend suite and the demo confirm it.
