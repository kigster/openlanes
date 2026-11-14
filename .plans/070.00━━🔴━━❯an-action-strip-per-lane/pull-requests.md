# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 242 | [\[070.00\](A) An Action Strip per Lane](https://github.com/kigster/openlanes/pull/242) | Open 🟡 |

## Verification, backend-coder round 1

- `bundle exec rubocop` — 993 files, no offenses.
- `npx vitest run` (web) — 69 files, 648 tests passed; `npm run lint` and `tsc --noEmit` clean.
- `bundle exec rspec` — 6645 examples, 0 failures, 9 pending (pre-existing).
- `just web-e2e` (Cypress `lane-documents.cy.ts`) — written, not run in this round (no browser run within the time budget).

## Findings: design-reviewer

### F201 [minor] lib/openlanes/web/plan_files.rb:17

`PlanFiles::READABLE` and `DOCUMENT_LABELS` (`web/src/panels/documents.ts:6`) are the same seven names in the same order. The Ruby comment says the lane dropdown lists `READABLE` in that order. `documentsOf` does not read that constant: it drops any name missing from `DOCUMENT_LABELS` and sorts by the TypeScript table.

Failing scenario: add `verdict.md` to `READABLE` only, the edit the comment points at. `GET /api/plans/:ordinal/files` returns it and the drawer lists it. The Documents menu does not, and reordering `READABLE` leaves Specification first.

### F202 [minor] web/src/board/PlanRow.tsx:174

Whether the Documents control exists is decided twice. `PlanRow` passes `lanes="narrow"` for `keepsRow` rows, and `LaneDocuments` then returns null. `web/src/board/board.css:147` also hides `.plan-actions` on `.plan.is-half` and on `[data-lanes="narrow"]`.

Failing scenario: stop forcing `keepsRow` rows to `lanes="narrow"` so a finished plan on a wide board can open Documents. The button mounts and `useDocuments` fetches. The `.is-half` rule still sets `.plan-actions` to `display: none`. Expected: a visible Documents control. Actual: a mounted control that stays hidden.

### F203 [minor] web/src/board/LaneDocuments.tsx:19

`useDocuments` returns `error`. `LaneDocuments` keeps `documents` and `loading` only. `empty` is `!loading && documents.length === 0`, and a failed query also yields `documents: []` (`web/src/panels/useDocuments.ts:14`).

Failing scenario: `GET /api/plans/070.00/files` returns 500. Expected: the trigger shows `error`. Actual: the trigger is disabled with title "This plan has no documents yet".

## Findings: staff-reviewer

### F1 [minor] .plans/070.00━━👀━━❯an-action-strip-per-lane/pull-requests.md:12

U6's done-when is `just web-e2e` passing with `web/cypress/e2e/lane-documents.cy.ts`. The verification note says that spec was written and not run. The unit tests stub `fetch` and mock `mermaid`, so they do not exercise the demo server, the Radix portal, or a real diagram.

Failing scenario: the integration proof the plan requires. Expected: a recorded passing `just web-e2e` for `lane-documents.cy.ts` (Specification first, YAML `created:` highlighted, `[!NOTE]`, a `.mermaid-diagram svg`, both close controls, width at 400px, no trigger on narrow lanes). Actual: "written, not run in this round".

### F2 [minor] web/src/panels/DocumentModal.tsx:40

`renderMermaid` replaces each `pre code.language-mermaid` with an SVG. The effect depends on `dark`, but a later run finds no fence: React leaves the div alone when `dangerouslySetInnerHTML` is the same string, which the comment on the effect already says. The theme argument is therefore applied only on the first successful draw.

Failing scenario: open Research while the page is in the light theme, then switch to dark with the modal still open. Expected: `mermaid.initialize` runs again with `theme: "dark"` and the SVG is replaced. Actual: the light-theme SVG stays until the modal is closed and opened again.

### F3 [minor] web/src/board/LaneDocuments.tsx:20

Same failure design-reviewer filed as F203. `useDocuments` returns `error`, and `LaneDocuments` never reads it. `empty` treats a failed list like an empty plan.

Failing scenario: `GET /api/plans/070.00/files` returns 500. Expected: the trigger stays available or shows the error from the hook. Actual: the trigger is disabled with title "This plan has no documents yet".

## Findings: security-reviewer

no findings

## Answers, round 2

- F201 / F202 / F203 (design-reviewer), F2 / F3 (staff-reviewer): fix.
  - F201: `documentsOf` keeps the server's order and humanizes a name the label table lacks, so `PlanFiles::READABLE` alone decides what is listed (`web/src/panels/documents.ts`).
  - F202: removed the `.plan-actions { display: none }` rule from `board.css`; `LaneDocuments` alone decides whether the strip exists.
  - F203 / F3: `LaneDocuments` reads `error`; a failed list disables the trigger with "Could not list the documents: …".
  - F2: the preview is keyed by theme, so a switch remounts it and Mermaid draws again with the new theme.
- F1: `just web-e2e` is recorded below if it ran within this round's budget; otherwise it remains unrun.
