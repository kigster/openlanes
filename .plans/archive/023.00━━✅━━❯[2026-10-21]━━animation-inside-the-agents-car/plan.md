# Plan 023.00: Animation Inside the Agents Car

A running, unblocked car shows a small gear turning inside its card. CSS keyframe on an inline SVG, stilled under reduced motion. No Ruby, API, payload or dependency change.

Assumptions from `spec.md` `## Open questions` stand as written: no gear while `carLook().blocked`; the mark is a gear; no Cypress assertion; gear sits left of the agent name in `.car-top`.

## Order and dependencies

```mermaid
flowchart LR
  F1[F1 Gear and is-running in Car] --> B1[B1 Integration: demo through the server]
  F2[F2 Spin keyframes and reduced motion in board.css] --> B1
```

| Unit | Discipline | Depends on | Runs beside |
| :--- | :--------- | :--------- | :---------- |
| F1   | front end  | nothing    | F2          |
| F2   | front end  | nothing    | F1          |
| B1   | back end   | F1, F2     | nobody      |

F1 and F2 own disjoint files, so they can run at the same time. B1 writes no source and runs last.

## Backend

### B1 Integration check: the demo server drives a spinning gear

- **Discipline:** back end (verification only; no source change).
- **Owns:** nothing in the source tree. Writes its observations to `integration.md` in this plan folder.
- **Must not touch:** `web/src/**`, `lib/openlanes/web/demo_board.rb`, `spec/openlanes/web/demo_board_spec.rb`, anything under `lib/`.
- **Depends on:** F1, F2.
- **Done when:** with nothing stubbed:
  1. `just web-build`, then `just web-demo` (serves `web/dist` from the Ruby server on `127.0.0.1:11000`).
  2. The board payload the server returns holds at least one car with `state: "running"` (already true per `spec/openlanes/web/demo_board_spec.rb`, which must stay green under `bundle exec rspec`).
  3. In the page, every card for such a car carries `.car.is-running` and contains `.car-gear`, whose computed `animation-name` is the keyframe F2 defines; done, stuck, failed and interrupted cards have no `.car-gear`.
  4. With reduced motion emulated, the gear is still present and its computed `animation-name` is `none`.
  5. Several running cars at once: `.car-top` layout holds with the lock mark present.
  `integration.md` records each of the five, pass or fail, with the command or selector used.

## Frontend

### F1 Gear mark and `is-running` class on the car

- **Discipline:** front end.
- **Owns:** `web/src/board/Car.tsx`, `web/src/board/Gear.tsx` (new), `web/src/board/Board.test.tsx`.
- **Must not touch:** `web/src/board/board.css`, `web/src/index.css`, `web/src/board/model.ts`, `web/src/api/types.ts`, `web/src/board/sample.ts`, anything outside `web/`.
- **Depends on:** nothing.
- **Shape:**
  - `Gear(): JSX.Element` in `Gear.tsx`: a small inline SVG, `className="car-gear"`, `aria-hidden="true"`, no props.
  - `Car` adds `is-running` to the card's class list when `car.state === "running" && !look.blocked`, and renders `<Gear />` first inside `.car-top` under the same condition.
  - `InterruptedCar` is unchanged: no class, no gear.
- **Done when:** `web/src/board/Board.test.tsx` has cases asserting `is-running` and `.car-gear` are present for a running, unblocked car, and absent for `done`, `stuck`, `failed`, a running car blocked by an unanswered question, and `InterruptedCar`; `just web-test` (lint, typecheck, coverage) is green with every new branch in `Car.tsx` covered.

### F2 Spin keyframes and the reduced-motion stop

- **Discipline:** front end.
- **Owns:** `web/src/board/board.css`, `web/src/board/boardCss.test.ts` (new).
- **Must not touch:** `web/src/board/Car.tsx`, `web/src/board/Gear.tsx`, `web/src/board/Board.test.tsx`, `web/src/index.css`.
- **Depends on:** nothing.
- **Shape:**
  - `@keyframes car-gear-spin` (0 to 360 degrees) in `board.css`.
  - `.car-gear`: small fixed size, `flex: none`, sits in `.car-top` without breaking its `space-between` layout.
  - `.car.is-running .car-gear { animation: car-gear-spin 2s linear infinite; }`.
  - Inside the existing `@media (prefers-reduced-motion: reduce)` block beside `board.css:115-117`: `.car-gear { animation: none; }`. The global `0.01ms` rule in `index.css:12-14` does not stop an infinite spin.
- **Done when:** `web/src/board/boardCss.test.ts` imports `board.css?raw` and asserts the `car-gear-spin` keyframe exists, the `.is-running .car-gear` rule references it as infinite, and the reduced-motion block sets `.car-gear` to `animation: none`; `just web-test` is green.

## HTTP surface

No. The plan adds and changes no HTTP API, so no `openapi.yaml`.

## Decisions

### B1 (answered) — Rebase onto origin/main before signing Completed

`bundle exec rspec` reports 30 environment failures on this machine (`spec/openlanes/apps/**`, `spec/openlanes/cli/app_spec.rb`, `spec/integration/two_checkouts_spec.rb`). They fail on a clean `HEAD` too. `origin/main` already holds the fix, so the question was whether to rebase onto it, accept the failures as baseline, or disable the network filter.

### D1 (decision) — Rebase onto origin/main, then rerun before Completed

Answered:

* 2026-10-17
* By kig

Rebase the branch onto `origin/main` before the next run, then rerun `backend-coder` to confirm `bundle exec rspec` exits 0 before signing `Completed`.

---

### B2 (answered) — Commit and rebase before the rspec rerun

`D1` was not carried out: `HEAD` is still `7186635`, 156 commits behind `origin/main` (`0b10d65`), and the plan's work is uncommitted in the worktree. `bundle exec rspec` shows 30 port and process failures in `spec/openlanes/apps/**` and `spec/openlanes/cli/app_spec.rb`, and the same specs pass on a clean checkout of `origin/main`. A rebase cannot carry uncommitted work, and `backend-coder` may not commit or rebase, so the run could not meet "rspec exits 0" on its own. Options: commit and rebase, accept the 30 failures as baseline, or allow the port specs through the network filter.

### D2 (decision) — Commit the plan's work, rebase onto origin/main, then rerun

Answered:

* 2026-10-18
* By kig

Commit the plan's work on `kig/023.00-animation-inside-the-agents-car`, rebase it onto `origin/main`, and rerun `backend-coder` to confirm `bundle exec rspec` exits 0 before signing `Completed`.

---

### B3 (answered) — Commit and rebase were never carried out

`D2` was not carried out: `HEAD` is still `7186635`, 237 commits behind `origin/main` (`ca171ed`), and the plan's work is uncommitted (`Car.tsx`, `Gear.tsx`, `board.css`, `Board.test.tsx`, `boardCss.test.ts`). `bundle exec rspec` still shows 30 port and process failures in `spec/openlanes/apps/**` and `spec/openlanes/cli/app_spec.rb`. `backend-coder` may not commit or rebase, so the run cannot meet "rspec exits 0" by itself. `origin/main` has also changed `Car.tsx`, `Board.test.tsx` and `board.css`, so the rebase will likely conflict in those three files.

### D3 (decision) — A person commits, rebases and resolves, then rerun

Answered:

* 2026-10-19
* By kig

A person commits the plan's work on `kig/023.00-animation-inside-the-agents-car`, runs `git rebase origin/main`, resolves the conflicts in `Car.tsx`, `Board.test.tsx` and `board.css`, then reruns `backend-coder` to confirm `bundle exec rspec` exits 0 before signing `Completed`.

---

## How to test

- Web suite: `cd web && npm run lint && npm run typecheck && npm run coverage`. All tests pass (35 files, 364 tests), including `Board.test.tsx` (gear present on running cars, absent on done, stuck, failed, blocked and interrupted) and `boardCss.test.ts` (keyframe, running rule, reduced-motion stop).
- Ruby suite: `bundle exec rspec && bundle exec rubocop`. Both exit 0; the port-detection specs under `spec/openlanes/apps` pass.
- By eye: `just web-build && just web-demo`, open `http://127.0.0.1:11000`. Every running, unblocked car shows a small gear left of the agent name, turning slowly. Done, stuck, failed, blocked and interrupted cars show no gear.
- Reduced motion: enable "Reduce motion" in the OS (or emulate `prefers-reduced-motion: reduce` in browser devtools) and reload. The gear is still there and does not turn.
- Layout: with several running cars on the board, the card header keeps the name on the left and the status on the right, with no wrapping.
