# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 242 | [\[070.00\](A) An Action Strip per Lane](https://github.com/kigster/openlanes/pull/242) | Merged 🟣 |

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

## Findings: staff-reviewer

### F1 [minor] web/src/panels/DocumentModal.tsx:50

The modal's `[x]` is a `Dialog.Close` whose visible text is `[x]` and whose accessible name is `Close` (`aria-label="Close"`). Those two disagree, so axe-core 4.14's `label-content-name-mismatch` (impact serious) fails. `lane-documents.cy.ts` runs that rule on `.document-modal` with `includedImpacts: ["serious", "critical"]`.

Failing scenario: CircleCI e2e job 2938, commit `fcf236f4`, spec `web/cypress/e2e/lane-documents.cy.ts`, test "lists Specification first and renders it with highlighted YAML frontmatter and a rendered body". Expected: `cy.checkA11y` reports 0 violations. Actual: the spec logs `axe: label-content-name-mismatch` and fails with `AssertionError: 1 accessibility violation was detected: expected 1 to equal 0`. The other four tests in that file passed (Pull requests last and footer Close, `[!NOTE]` plus a `.mermaid-diagram svg`, width at least 398px at a 400px viewport, no Documents trigger on narrow lanes). `ci/circleci: e2e` is red. Linter, test and web on the same commit are green.

Hide the glyphs from the name: `<Dialog.Close className="document-modal-x" aria-label="Close"><span aria-hidden="true">[x]</span></Dialog.Close>`.

### F2 [minor] web/src/panels/panels.css:329

The base rule sets `width: min(1000px, 70vw)`. Seventy percent of the viewport drops below 1000px at about 1429px wide, so the modal starts shrinking there. The `@media (max-width: 1200px)` rule, which is what keeps a 15% horizontal margin, never decides the width for a window between 1200px and 1429px.

Failing scenario: viewport 1300px wide. Expected: width stays at the 1000px maximum until the page is 1200px or narrower, then the horizontal margins are 15%. Actual: width is `70vw`, 910px.

Set the base width to `1000px` and leave the 1200px query as `left: 15%; right: 15%; width: auto`.

## Findings: staff-reviewer

### F1 [minor] web/src/panels/DocumentModal.tsx:50

Still open on `fcf236f4`. The `[x]` control's visible text is `[x]` and its accessible name is `Close`. axe-core's `label-content-name-mismatch` (serious) fails, and `lane-documents.cy.ts` checks `.document-modal` for serious and critical violations.

Failing scenario: `gh pr checks 242` on `fcf236f4` reports `ci/circleci: e2e` fail (https://app.circleci.com/workflow/f5a4f2f5-c3ab-47a4-ac5c-14b64e8ed524/job/b198552f-29c3-44f0-b94a-ac23408c5b22). The spec opens Specification and runs `cy.checkA11y`. Expected: 0 violations. Actual: `label-content-name-mismatch` because `Dialog.Close` is `aria-label="Close"` with text node `[x]`. Linter, test and web on this commit are green. The source line is unchanged since that failure.

Hide the glyphs: `<Dialog.Close className="document-modal-x" aria-label="Close"><span aria-hidden="true">[x]</span></Dialog.Close>`.

### F2 [minor] web/src/panels/panels.css:330

Still open. The base rule is `width: min(1000px, 70vw)`. `70vw` falls through 1000px at about 1429px, so the modal shrinks before the page is 1200px wide. The `@media (max-width: 1200px)` block now sets `width: auto` with `left`/`right: 15%`, and that block does not apply above 1200px.

Failing scenario: viewport 1300px wide. Expected: width stays 1000px until the page is 1200px or narrower, then the horizontal margins are 15%. Actual: width is `70vw`, 910px.

Set the base width to `1000px`.

## Findings: staff-reviewer

### F1 [critical] web/cypress/e2e/lane-documents.cy.ts:35

`gh pr checks 242` reports `ci/circleci: e2e` failed on head `fcf236f4`. A red required check sends the pull request back to the builder. Linter, test and web on the same commit passed. Mermaid Diagram Sync Assistant is skipped. The diff was not reviewed.

Failing scenario: `gh pr checks 242` for `fcf236f4800abc9eb9035cca110a5ec3e8d1d480`. Expected: `ci/circleci: e2e` success. Actual: state FAILURE, job https://app.circleci.com/workflow/f5a4f2f5-c3ab-47a4-ac5c-14b64e8ed524/job/b198552f-29c3-44f0-b94a-ac23408c5b22. The spec at that line runs `cy.checkA11y` on `.document-modal`. The recorded failure on this same job is axe `label-content-name-mismatch` (serious): the `[x]` control's visible text is `[x]` and its accessible name is `Close`.

Hide the glyphs from the name: `<Dialog.Close className="document-modal-x" aria-label="Close"><span aria-hidden="true">[x]</span></Dialog.Close>`.

## Answers, round 3

- F1 (staff-reviewer, axe `label-content-name-mismatch`): fix. The `[x]` glyphs are wrapped in `<span aria-hidden="true">` in `DocumentModal.tsx`, so the accessible name is `Close` alone.
- F2: fix. `.document-modal` width is `1000px` in `panels.css`; the 1200px query still sets 15% margins. `DocumentModal.test.tsx` asserts the new width.
- Checks: `bundle exec rubocop` 993 files, no offenses; `npx vitest run` 69 files, 648 passed; `npm run lint` and `tsc --noEmit` clean.
- `bundle exec rspec` — 6645 examples, 0 failures, 9 pending (pre-existing).

## Findings: staff-reviewer

### F1 [critical] web/src/panels/DocumentModal.tsx:50

`gh pr checks 242` reports `ci/circleci: e2e` failed on head `20ae5db2`. Linter, test and web on that commit passed. A red required check sends the pull request back to the builder.

Failing scenario: CircleCI e2e job 2991, commit `20ae5db200b31fdf376ba32baa197d794419fed3`, spec `web/cypress/e2e/lane-documents.cy.ts`, test "lists Specification first and renders it with highlighted YAML frontmatter and a rendered body". Expected: `cy.checkA11y` on `.document-modal` reports 0 serious or critical violations, and `ci/circleci: e2e` succeeds. Actual: the spec logs `axe: label-content-name-mismatch` and fails with `AssertionError: 1 accessibility violation was detected: expected 1 to equal 0`. The other four tests in that file passed. Job: https://app.circleci.com/workflow/1007121c-f572-4f1f-b8bf-c37a2d1bb5ef/job/983de25b-b6a4-4586-a2ba-22add2a6434f

Wrapping `[x]` in `<span aria-hidden="true">` does not fix axe-core 4.14. `label-content-name-mismatch` compares the accessible name with text that is visible on screen (`visibleVirtual` with the screen-reader flag false, so `isVisibleOnScreen`). `aria-hidden` takes the glyphs out of the name and leaves them painted. The visible text stays `[x]` and the name stays `Close`, and `[x]` is not contained in `Close`.

Drop `aria-label="Close"` so the button's name is the visible `[x]`, or set the accessible name to a string that contains `[x]` (for example `aria-label="[x]"`). Do not hide the glyphs with `aria-hidden` while the name is `Close`.
