---
created: 2026-10-15
starts: research
---

# Draggable divider between the lanes and the right-hand panel

## Problem statement

The column to the right of the lanes board is fixed at 360px (`web/src/shell/shell.css:53`). When a car is open, its `AgentDrawer` often holds more than that width shows, and the only remedy is to scroll. The user wants to drag the boundary between the lanes area and that column to widen it. This is a UI-only change; no backend is involved.

## Framings

1. **A resizable column.** Treat the right column as one panel whose width the user sets. Whatever it shows (`AgentDrawer` or `NeedsYou`, `web/src/App.tsx:307-310`) gets the same width.
1. **A wider drawer only.** Treat it as a drawer feature: the width applies when a car is open and `NeedsYou` stays at 360px.

**Picked: 1.** Both panels occupy the same grid track, so a width that changes when a car opens or closes would make the board jump. One track, one width.

## Goal

The user can drag a handle on the boundary between the lanes board and the right-hand column to make that column wider or narrower, within limits, and the chosen width is still there after a reload. Today the width cannot be changed at all.

## Non-Goals

- Resizing the lanes board itself, its stations or its cards. The board takes whatever the column leaves (`web/src/board/board.css:6`).
- Any backend, API, `state.json` or `.openlanes.yml` change.
- A general splitter component for other panels, or changes to `useFloatingPanel`.
- Moving the column to the left or bottom, or making it collapsible.
- Changing the single-column layout at 960px and below.

## In scope

1. A handle sits between the board and the right column on viewports wider than 960px. Check: it renders in the DOM with `role="separator"` and `aria-orientation="vertical"`, and is absent at 960px and below.
1. Dragging the handle with a pointer changes the column width in real time, and the grab does not jump. Check: a Vitest or Cypress test dispatches pointerdown, move, up and asserts the computed width of `.drawer`.
1. Width is clamped to a minimum of 360px (today's width) and a maximum of 60% of the layout width. Check: tests drag past each bound and assert the clamped value.
1. The width applies to whichever panel is shown, `AgentDrawer` or `NeedsYou`, and is kept when switching between them. Check: open and close a car and assert the width is unchanged.
1. The width persists in `localStorage` under a new key in the shape of `openlanes-merged` (`web/src/App.tsx:36-52`), tolerating a throwing `localStorage`. Check: a test stores a width, remounts, and asserts it; another stubs `localStorage` to throw and asserts the default.
1. Keyboard: the handle is focusable, Left/Right arrows change the width by a fixed step, Home resets to 360px (amended: to the default clamp, see the round 2 deviation in open questions). Check: keyboard test asserting `aria-valuenow` changes.
1. Double-clicking the handle resets the width to 360px (amended: to the default clamp, see the round 2 deviation). Check: test.
1. Default behaviour with no stored value is unchanged: 360px (amended: `main` already had `clamp(360px, 30vw, 432px)`, so unchanged means that clamp). Check: existing `App.test.tsx` and Cypress specs that select `.drawer` still pass.

## Out of scope

- Touch-specific gestures beyond what pointer events give: pointer events already cover touch, and no separate design is needed.
- Per-machine or per-plan stored widths: one global value is enough and matches `openlanes-merged`.
- Animating the resize: a drag is direct manipulation.
- Syncing the width across browser tabs: `localStorage` is read on load only.

## Back end / front end

| Item | Back end (`backend-coder`) | Front end (`frontend-coder`) |
| :--- | :--- | :--- |
| 1 to 8 | Nothing. | Everything: `web/src/shell/shell.css`, `web/src/App.tsx`, a new hook beside `web/src/floating/useFloatingPanel.ts`, tests. |

backend-coder has no work. If `planner` needs a pair, backend-coder's unit is to run `bundle exec rspec spec/openlanes/web` and confirm the served bundle is unaffected (167 examples, 0 failures at research time).

## Open questions

Each carries the default this spec assumes. A human can change it without reshaping the plan.

1. Does the divider govern `NeedsYou` as well as `AgentDrawer`? **Assumed: yes**, one column, one width (see Framings).
1. Minimum and maximum width. **Assumed:** min 360px, max 60% of the layout width. Research gives only today's fixed 360px.
1. Does the width persist across reloads? **Assumed: yes**, in `localStorage`.
1. At 960px and below, is the divider dropped? **Assumed: yes**, the single-column layout is untouched (`web/src/shell/shell.css:54`).
1. Keyboard support. **Assumed: yes**, arrows, Home; no precedent exists in `web/src`, so step size (assumed 24px) is a guess.
1. Is a narrower-than-360px column ever wanted? **Assumed: no.**

1. **Deviation (round 2):** the spec says the default and the Home/double-click reset are 360px. `main` already had `clamp(360px, 30vw, 432px)` for that column, so the default and reset value are that clamp (420px in a 1400px window); 360px stays the drag minimum. Points 6, 7 and 8 read accordingly.
1. Not run at research: Vitest and Cypress (`web/node_modules` is absent). Baseline pass state of `App.test.tsx` and the Cypress specs is unknown until dependencies are installed.

## Risks to planning or execution

- `AgentDrawer` and `NeedsYou` are siblings inside the same `main.layout` as the tab contents (`web/src/App.tsx:300-311`). A handle needs its own grid track or an absolutely positioned element; the planner should decide which before splitting units, since the first changes the grid template and the second does not.
- `.drawer` is `position: sticky`-like and scrolls itself (`web/src/panels/panels.css:37`); a handle positioned relative to it can scroll away. Verify in a browser, not only in jsdom.
- A wide column pushes the board into horizontal scroll (`web/src/board/board.css:6`). That is accepted, but the 60% cap exists to keep the board usable.
- Frontend suites cannot be run in this worktree until `web/node_modules` is installed; the executor must do that first.
- Pointer capture is not implemented by jsdom, so drag tests may need Cypress or a stub.

## Conclusion

When this ships, a vertical handle between the lanes board and the right-hand column can be dragged, nudged with arrow keys, or double-clicked to reset. The column stays between 360px and 60% of the layout, its width survives a reload, and below 960px the page is unchanged. No Ruby code changes.

## Research

### Current layout

- One grid: `.layout { grid-template-columns: minmax(0, 1fr) 360px; gap: 20px }` (`web/src/shell/shell.css:53`). The 360px column is the drawer side.
- At 960px and below it collapses to one column (`web/src/shell/shell.css:54`), and `.drawer` goes `position: static` (`web/src/panels/panels.css:38`). A divider has no meaning there.
- The right column shows `AgentDrawer` when a car is open (`web/src/App.tsx:307-308`), otherwise `NeedsYou` (`web/src/App.tsx:310`).
- `.drawer` scrolls on its own (`web/src/panels/panels.css:37`). `.board-inner` has a `min-width` from the station count (`web/src/board/board.css:6`), so a wider drawer scrolls the board rather than clipping it.
- No splitter or drag-resize component exists in `web/src`. The only `.divider` is a pill separator (`web/src/shell/shell.css:150`).

### Reusable precedents

- Pointer drag: `useFloatingPanel` captures the pointer with `setPointerCapture`, releases it on up, and keeps the grab offset so the panel does not jump (`web/src/floating/useFloatingPanel.ts:106,116`).
- Persistence: a boolean lives in `localStorage` behind try/catch for private windows (`web/src/App.tsx:36-52`, key `openlanes-merged`). A stored width would follow the same shape.

### Verification

- `bundle exec rspec spec/openlanes/web` (2026-10-15): 167 examples, 0 failures. This is the Ruby side only.
- `web/node_modules` is absent in this worktree, so the Vitest and Cypress suites were not run. The ones that cover the drawer are `web/src/App.test.tsx` and `web/cypress/e2e/actions.cy.ts`, `keyboard.cy.ts` (they select `.drawer`). Install dependencies before relying on them.
- Running rspec rewrote `docs/badges/coverage_badge.svg`. Reverted with `git checkout`.

### Contradictions

- The spec calls the right-hand side "the drawer", but the same column shows `NeedsYou` when no car is open (`web/src/App.tsx:310`). The spec does not say whether the divider governs that panel too.
- Code read: the checked-out worktree only. I did not check a deployed build.

### Open questions

1. Does the divider resize `NeedsYou` as well as `AgentDrawer`, or only the drawer?
2. Minimum and maximum drawer width. Today it is fixed at 360px.
3. Does the chosen width persist across reloads (like `openlanes-merged`), or last only for the session?
4. At 960px and below, is the divider dropped (single column, as now) or does the drawer go full width?
5. Keyboard support for the divider (focus, arrow keys). No precedent exists in `web/src`.

### Findings, Conclusion & References

- The change is a CSS grid edit on `.layout` plus a pointer handler in the same style as `useFloatingPanel`. No backend is involved.
- Feasible with existing patterns. Open questions 1 to 5 are product choices for spec-writer to lift into the spec's open questions. None blocks research.
- References (repo, read at `git` HEAD `ce65c43`):
  - `web/src/shell/shell.css:53-54`, `web/src/panels/panels.css:37-38`, `web/src/App.tsx:36-52,307-310`, `web/src/board/board.css:6`, `web/src/shell/shell.css:150`, `web/src/floating/useFloatingPanel.ts:106,116`
  - Command: `bundle exec rspec spec/openlanes/web`, output above.
  - External sources: none consulted; none needed.

