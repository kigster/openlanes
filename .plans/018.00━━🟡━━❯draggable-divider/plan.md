# Plan 018.00: draggable divider between the lanes and the right-hand panel

## Decisions this plan makes

- **Handle placement: absolutely positioned, not a third grid track.** `main.layout` holds every `Tabs.Content` plus the right-hand panel as auto-placed grid children (`web/src/App.tsx:300-311`). A third track would force explicit `grid-column` on every child. Instead `.layout` gets `position: relative` and `grid-template-columns: minmax(0, 1fr) var(--side-width, 360px)`, and the handle is a direct child of `main.layout`, `position: absolute`, spanning the layout's height in the 20px gap. Because it is a child of `.layout` and not of `.drawer`, it does not scroll away with the drawer (spec risk 2).
- **Absent at 960px and below via `matchMedia("(min-width: 961px)")`**, not CSS `display: none`, because the spec's check is "absent from the DOM". `web/src/test/setup.ts:11` already stubs `matchMedia` to `matches: false`, so every existing `App.test.tsx` case renders without the handle and stays unchanged.
- **Storage key `openlanes-side-width`**, an integer in px, read and written behind try/catch exactly like `openlanes-merged` (`web/src/App.tsx:36-52`). An unparseable or throwing read yields 360.
- **Constants:** `MIN_SIDE = 360`, `MAX_SIDE_RATIO = 0.6` (of the `.layout` element's `clientWidth`), `SIDE_STEP = 24`. The stored value is re-clamped on load and on window resize, since a width saved on a large screen may exceed 60% of a small one.
- **Reuse `clamp` from `web/src/floating/useFloatingPanel.ts`**; no change to `useFloatingPanel` itself (non-goal).

## Order and dependency graph

```
F1 useSideWidth hook ──► F2 ColumnDivider component ──► F3 wire into App + CSS ──► F4 Cypress integration check
                                                                              └──► B1 Ruby-side bundle check
```

F1 → F2 → F3 → F4 are sequential: each consumes the previous unit's export, and F3 is the only unit that edits `App.tsx` and `shell.css`. B1 depends only on F3 and owns no source file, so it may run beside F4.

Before any front-end unit: `just web-install` (`web/node_modules` is absent in this worktree), then `just web-test` once to record the baseline.

## Backend

### B1 Served bundle unaffected

- **Discipline:** back end.
- **Owns:** nothing in source. Runs checks only. If `docs/badges/coverage_badge.svg` is rewritten by rspec, revert it with `git checkout`.
- **Must not touch:** anything under `web/` or `lib/`.
- **Depends on:** F3.
- **Done when:** `bundle exec rspec spec/openlanes/web` reports 0 failures (167 examples at research time), and `just web-build` succeeds so `openlanes web` serves a bundle containing the divider. Result recorded in the ledger note.

## Frontend

### F1 `useSideWidth` hook

- **Discipline:** front end.
- **Owns:** `web/src/floating/useSideWidth.ts` (new), `web/src/floating/useSideWidth.test.ts` (new), `web/src/floating/index.ts` (one export line).
- **Must not touch:** `web/src/floating/useFloatingPanel.ts`, `web/src/App.tsx`, any CSS.
- **Depends on:** nothing.
- **Shape:** `useSideWidth(layoutRef: RefObject<HTMLElement | null>): { width: number; min: number; max: number; wide: boolean; setWidth(px: number): void; nudge(deltaPx: number): void; reset(): void }`. Exports `MIN_SIDE`, `MAX_SIDE_RATIO`, `SIDE_STEP`, `SIDE_WIDTH_KEY`. `setWidth` clamps and persists; `wide` tracks the `(min-width: 961px)` media query.
- **Done when:** `useSideWidth.test.ts` passes, covering: default 360 with nothing stored; stored value restored on remount; a throwing `localStorage` (get and set) yields 360 and does not throw; clamp below 360 and above 60% of the layout width; `reset` returns to 360 and persists; `wide` follows a stubbed `matchMedia`.

### F2 `ColumnDivider` component

- **Discipline:** front end.
- **Owns:** `web/src/shell/ColumnDivider.tsx` (new), `web/src/shell/ColumnDivider.test.tsx` (new).
- **Must not touch:** `web/src/App.tsx`, `web/src/shell/shell.css`, F1's files.
- **Depends on:** F1.
- **Shape:** `ColumnDivider({ width, min, max, onResize(px), onNudge(deltaPx), onReset, layoutRef })`. Renders `<div role="separator" aria-orientation="vertical" aria-label="Resize side panel" aria-valuenow aria-valuemin aria-valuemax tabIndex={0} className="col-divider">`. Pointer: down captures (`setPointerCapture?.`, as `useFloatingPanel.ts:116`) and records the grab offset between the pointer and the column's left edge so the grab does not jump; move computes the new width from the layout's right edge; up releases. Keys: ArrowLeft widens by `SIDE_STEP`, ArrowRight narrows by `SIDE_STEP` (the column is on the right, so moving the boundary left widens it), Home resets. Double-click resets.
- **Done when:** `ColumnDivider.test.tsx` passes, covering: the ARIA attributes; pointerdown/move/up calls `onResize` with the offset-corrected width (pointer capture stubbed, since jsdom lacks it); ArrowLeft, ArrowRight and Home call through; double-click calls `onReset`.

### F3 Wire the divider into the layout

- **Discipline:** front end.
- **Owns:** `web/src/App.tsx`, `web/src/shell/shell.css`, `web/src/App.test.tsx`.
- **Must not touch:** `web/src/panels/panels.css`, `web/src/board/board.css`, `web/src/floating/useFloatingPanel.ts`, F1's and F2's files.
- **Depends on:** F2.
- **Shape:** `App` holds a ref on `main.layout`, calls `useSideWidth`, sets the `--side-width` custom property (`${width}px`) in `main.layout`'s inline style, and renders `<ColumnDivider>` as a direct child of `main.layout` only when `wide`. `shell.css`: `.layout` gets `position: relative` and `grid-template-columns: minmax(0, 1fr) var(--side-width, 360px)`; `.col-divider` is absolutely positioned at `right: calc(24px + var(--side-width, 360px))` (the layout's right padding) with the 20px gap as its width, full height, `cursor: col-resize`, `touch-action: none`, and a visible `:focus-visible` ring. The 960px media query keeps its single-column template untouched.
- **Done when:** `App.test.tsx` passes unchanged, plus new cases there: with `matchMedia` stubbed wide, the separator renders and `--side-width` on `.layout` follows a stored value; with the default stub, no separator renders; opening and closing a car leaves `--side-width` unchanged. `just web-test` (lint, typecheck, coverage) is green.

### F4 Integration check: Cypress against the real demo server

- **Discipline:** front end.
- **Owns:** `web/cypress/e2e/divider.cy.ts` (new).
- **Must not touch:** any `web/src` file, the other Cypress specs, `web/cypress/support/*`.
- **Depends on:** F3.
- **Integration check:** this is the plan's one unit with nothing stubbed. Run through `just web-build && just web-e2e`, which serves the built bundle from `openlanes web --demo` and drives a real browser against its real `/api`. It must show, at a 1400px-wide viewport:
  1. a `[role="separator"][aria-orientation="vertical"]` between the board and `.drawer`;
  2. a pointer drag changes `.drawer`'s computed width by the dragged distance, with no jump at pointerdown;
  3. dragging past either bound clamps at 360px and at 60% of `.layout`'s width;
  4. after `cy.reload()` the width is the dragged one;
  5. opening a car (`AgentDrawer`) and closing it (back to `NeedsYou`) keeps the width;
  6. arrow keys change `aria-valuenow` by 24; Home and double-click return it to 360;
  7. the handle stays visible after scrolling the drawer;
  8. at a 900px-wide viewport the separator does not exist.
- **Done when:** `divider.cy.ts` passes under `just web-e2e`, and `actions.cy.ts`, `keyboard.cy.ts` and the other existing specs still pass.

## HTTP surface

No. The plan adds and changes no HTTP API; no `openapi.yaml` is written.
