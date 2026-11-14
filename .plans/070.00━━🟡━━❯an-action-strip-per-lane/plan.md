---
execution: concurrent
---

Not a refactor: it adds a dropdown, a modal and one server list entry. Files touched ≈ 14 of 2206 tracked (0.6%), lines well under 1% of the tree; threshold 50%.

# Plan: An Action Strip per Lane

Each wide lane gets a small "Documents" dropdown at the bottom of its left-hand details block. The dropdown lists the
plan's markdown documents under English labels (Specification, Plan, Contract, Research, Design, Blocked, Pull requests)
and opens one in a document modal: frontmatter as a highlighted YAML block, then the body rendered with admonitions,
syntax highlighting, Mermaid diagrams and images. The modal sizes itself to the viewport as the spec says, has `[x]`
top right and a Close button in a footer. Narrow lanes and other machines' lanes show no dropdown.

`spec.md` says `frontend: false`, so every unit below is under `## Backend` and `backend-coder` builds all of it,
TypeScript included. There is deliberately no unit heading under `## Frontend`.

## What already exists, and is reused rather than rebuilt

- `GET /api/plans/:ordinal/files` and `GET /api/plans/:ordinal/files/:name` (`lib/openlanes/web/plan_files.rb`,
  `web/src/api/planFiles.ts`) list and read a plan's markdown by name. `pull-requests.md` is missing from `READABLE`.
- `web/src/panels/PlanFilePopup.tsx` already shows a file rendered through `renderMarkdown` inside a Radix `Dialog`
  via `Frame` (`dialogs.tsx`), with the frontmatter in a plain `<pre>`. It also edits spec.md and plan.md.
- `web/src/panels/markdown.ts` is marked + DOMPurify + highlight.js. No admonitions, no Mermaid.
- `web/src/board/PlanRow.tsx` renders one lane; `.plan-head` is the left details block; `[data-lanes="narrow"]` and
  `.is-half` hide the meta line (`board.css:142-154`). The car model dropdown is Radix Select (`ModelSelect.tsx`).
- Cypress `web/cypress/e2e/plan-files.cy.ts` already drives the drawer against the real demo server.

## Order and dependency graph

```
U1 (server: pull-requests.md readable)          U2 (labels + document hook)
        \                                         |
         \                                        v
U3 (markdown: admonitions, mermaid, yaml) ----> U4 (DocumentModal)
                                                  |
                                                  v
                                           U5 (LaneDocuments dropdown in PlanRow)
                                                  |
                                                  v
                                           U6 (integration e2e)
```

U1, U2 and U3 run in parallel. U4 waits for U3 (and U2 for the label type). U5 waits for U2 and U4. U6 waits for
everything. U4 and U5 both add rules to `web/src/panels/panels.css` and `web/src/board/board.css` respectively, which
are different files, so they do not collide; U3 and U4 both touch `panels.css` and therefore run sequentially (U3
first).

## Backend

### U1. The server lists `pull-requests.md`

- **Discipline:** back end (Ruby).
- **Owns:** `lib/openlanes/web/plan_files.rb`, `spec/openlanes/web/plan_files_spec.rb`.
- **Must not touch:** `lib/openlanes/web/app.rb` (the routes already cover any readable name), anything under `web/`.
- **Depends on:** nothing.
- **What:** add `pull-requests.md` to `PlanFiles::READABLE` after `blocked.md`, leaving `EDITABLE` alone so it stays
  read only. Order `READABLE` as the dropdown will show it: `spec.md plan.md contract.md research.md design.md
  blocked.md pull-requests.md`. Update the comment to say the lane dropdown reads this list too.
- **Done when:** `spec/openlanes/web/plan_files_spec.rb` lists `pull-requests.md` when present, reads it, and refuses
  to write it with `ReadOnly`; `bundle exec rspec spec/openlanes/web` and `rubocop` are green.

### U2. English labels and the document hook

- **Discipline:** back end (TypeScript, per `frontend: false`).
- **Owns:** `web/src/panels/documents.ts`, `web/src/panels/documents.test.ts`, `web/src/panels/useDocuments.ts`,
  `web/src/panels/useDocuments.test.tsx`.
- **Must not touch:** `web/src/api/planFiles.ts`, `PlanRow.tsx`, `markdown.ts`.
- **Depends on:** nothing.
- **What:** `documents.ts` exports `DOCUMENT_LABELS: ReadonlyArray<{ name: string; label: string }>` in display order
  (`spec.md` → "Specification", `plan.md` → "Plan", `contract.md` → "Contract", `research.md` → "Research",
  `design.md` → "Design", `blocked.md` → "Blocked", `pull-requests.md` → "Pull requests") and
  `documentsOf(files: string[]): Document[]` which keeps only names the plan has, in label order, Specification always
  first, and drops unknown names. `useDocuments(ordinal, enabled)` wraps `listPlanFiles` in `@tanstack/react-query`
  (`queryClient.ts` is already there), key `["plan-files", ordinal]`, `staleTime` 30s, disabled when `enabled` is
  false so narrow lanes and other machines' rows fetch nothing. Returns `{ documents, loading, error }`.
- **Done when:** `documents.test.ts` covers ordering, Specification-first, unknown names dropped, empty list; and
  `useDocuments.test.tsx` covers a disabled hook making no request and an enabled one mapping names to labels (fetch
  stubbed at the `fetch` boundary, as `planFiles.test.ts` does).

### U3. Markdown: admonitions, Mermaid, YAML frontmatter

- **Discipline:** back end (TypeScript).
- **Owns:** `web/src/panels/markdown.ts`, `web/src/panels/markdown.test.ts`, `web/src/panels/mermaid.ts`,
  `web/src/panels/mermaid.test.ts`, `web/package.json`, `web/package-lock.json`, `web/src/panels/panels.css` (the
  `.md-preview` admonition and `.mermaid` rules only).
- **Must not touch:** `PlanFilePopup.tsx`, `PlanRow.tsx`, `DocumentModal.tsx`.
- **Depends on:** nothing.
- **What:**
  - Add the `mermaid` npm package (pinned, like the other deps). `mermaid.ts` exports
    `renderMermaid(root: HTMLElement): Promise<void>` that finds `pre code.language-mermaid` under `root`, replaces
    each with a `<div class="mermaid-diagram">` holding the SVG from `mermaid.render`, and leaves the fenced source
    (with a `.mermaid-error` note) when rendering throws. Mermaid is imported dynamically so the board bundle does
    not pay for it until a modal opens. Theme follows `useIsDark` (`"dark"` / `"default"`).
  - `renderMarkdown` gains GitHub-style admonitions: a blockquote whose first line is `[!NOTE]`, `[!TIP]`,
    `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` becomes `<div class="admonition is-note">` with a title line. Done as a
    post-pass over the sanitized fragment, like the existing link and code passes. Existing behaviour (links, hljs,
    sanitising) is unchanged; existing tests keep passing.
  - New export `renderFrontmatter(yaml: string): string`: the raw block without its `---` delimiters, highlighted by
    hljs as `yaml`, returned as `<pre><code class="hljs language-yaml">…</code></pre>`.
  - `panels.css`: `.admonition` variants coloured from the Gruvbox variables already defined for `.md-preview`, and
    `.mermaid-diagram svg { max-width: 100%; height: auto; }`. Images: `.md-preview img { max-width: 100%; }`.
- **Done when:** `markdown.test.ts` covers each admonition kind, a non-admonition blockquote left alone, and
  `renderFrontmatter` output containing `hljs` spans; `mermaid.test.ts` covers one diagram rendered to SVG and one bad
  diagram leaving the source with the error note (mermaid mocked at the module boundary in vitest). `npm run lint` and
  `npm test` in `web/` green.

### U4. The document modal

- **Discipline:** back end (TypeScript).
- **Owns:** `web/src/panels/DocumentModal.tsx`, `web/src/panels/DocumentModal.test.tsx`, `web/src/panels/panels.css`
  (the `.document-modal*` rules, added after U3's rules).
- **Must not touch:** `PlanFilePopup.tsx` (the drawer keeps its editing popup unchanged), `dialogs.tsx`, `PlanRow.tsx`.
- **Depends on:** U2 (the `Document` type), U3 (`renderFrontmatter`, `renderMermaid`, admonitions).
- **What:** `DocumentModal({ ordinal, document, onClose })`, read only, mounted means open, as `PlanFilePopup` is.
  It uses Radix `Dialog` with its own `Dialog.Content` (not `Frame`, whose `.start` width is fixed at 1120px): title
  "`<ordinal>` · `<label>`", a `Dialog.Close` `[x]` button top right with `aria-label="Close"`, the body
  (`renderFrontmatter` in a `.document-frontmatter` block when the file has one, then `renderMarkdown` of the body
  into `.md-preview`, then `renderMermaid` on that node after mount), and a footer with one `Close` button. Reads
  through `readPlanFile` + `splitPlanFile`. Loading and error states as in `PlanFilePopup`.
  Sizing in `panels.css`, from the spec:
  - default: `top`/`bottom` margins 10vh (`max-height: 80vh`), `width: min(1000px, 70vw)`;
  - `@media (max-width: 1200px)`: horizontal margin 15% (`width: 70vw`);
  - `@media (max-width: 600px)`: margins 5% all round (`width: 90vw; max-height: 90vh`);
  - `@media (max-width: 450px)`: margins 1px (`width: calc(100vw - 2px); max-height: calc(100vh - 2px)`).
  Body scrolls inside the modal; head and foot stay put.
- **Done when:** `DocumentModal.test.tsx` covers: frontmatter rendered as YAML and body rendered (fetch stubbed);
  a file with no frontmatter shows no YAML block; the `[x]` and the footer Close both call `onClose`; Esc closes;
  a 404 shows the server's reason. A CSS test in the style of `boardCss.test.ts` asserts the four width rules exist in
  `panels.css`.

### U5. The lane's Documents dropdown

- **Discipline:** back end (TypeScript).
- **Owns:** `web/src/board/LaneDocuments.tsx`, `web/src/board/LaneDocuments.test.tsx`, `web/src/board/PlanRow.tsx`,
  `web/src/board/Board.tsx`, `web/src/App.tsx`, `web/src/board/board.css`, `web/src/board/Board.test.tsx` (one added
  case), `web/src/board/boardCss.test.ts` (one added case).
- **Must not touch:** `web/src/panels/*`, `web/src/api/*`.
- **Depends on:** U2, U4.
- **What:** `LaneDocuments({ ordinal, lanes })` renders a Radix `DropdownMenu` (the pattern of `ActionMenu.tsx`,
  styled small like `.model-trigger`) whose trigger reads "Documents ▾" with `aria-label="Documents of <ordinal>"`.
  Items come from `useDocuments(ordinal, enabled)`; choosing one sets `open: Document | null` and mounts
  `DocumentModal`. With no documents the trigger is disabled with a title saying so. `PlanRow` places it at the end
  of `.plan-head` as a new `.plan-actions` line, only when `!readOnly`, and passes `lanes` from a new optional
  `lanes?: "wide" | "narrow"` prop (`App.tsx:113` holds the value from `useLanes` and sets `data-lanes` on `<main>`;
  thread it through `Board` to `PlanRow` with one-line changes in `App.tsx` and `Board.tsx`, and treat `keepsRow(plan)`
  rows as narrow). `App.tsx` and `Board.tsx` are owned by U5 for those lines only. `board.css` hides `.plan-actions` under
  `[data-lanes="narrow"]` and `.is-half`, matching lines 142-154, and the hook is disabled in that case so hidden lanes
  cost no request.
- **Done when:** `LaneDocuments.test.tsx` covers: menu lists labels in order from a stubbed list; choosing
  "Specification" mounts the modal and closing unmounts it; disabled trigger with an empty list; nothing fetched when
  narrow. `Board.test.tsx` asserts another machine's row has no Documents trigger. `boardCss.test.ts` asserts the
  narrow rule hides `.plan-actions`.

### U6. Integration check, end to end

- **Discipline:** back end (Cypress, TypeScript).
- **Owns:** `web/cypress/e2e/lane-documents.cy.ts`, `web/cypress/support/selectors.ts` (one added selector).
- **Must not touch:** `plan-files.cy.ts`, any `src/` file.
- **Depends on:** U1 to U5.
- **What:** against the real demo server that `bin/web-e2e` starts (nothing intercepted), on a wide board: a lane's
  Documents dropdown lists "Specification" first; choosing it opens exactly one modal whose YAML block contains the
  spec's `created:` key highlighted and whose body is rendered HTML (an `<h1>` from the spec's title); a plan folder
  the test writes a `pull-requests.md` into (via `Cypress.env("plansDir")`, as `plan-files.cy.ts` does) then shows
  "Pull requests" as the last item; a fixture document containing a `[!NOTE]` admonition and a ` ```mermaid ` block
  renders an `.admonition.is-note` and an `svg` inside `.mermaid-diagram`; `[x]` closes; the Close button closes;
  at viewport 400px wide the modal is at least `100vw - 2px` wide; switching lanes to narrow removes every Documents
  trigger. Also an `axe` pass on the open modal, as the other e2e specs do.
- **Done when:** `just web-e2e` passes with the new spec, and `just ci` stays green.

## Frontend

No front-end units: `spec.md` says `frontend: false`, so `backend-coder` builds the TypeScript above.

## HTTP surface

No. No route is added or changed; U1 only widens the set of names the existing `GET /api/plans/:ordinal/files*`
routes accept. No `openapi.yaml` is needed.

## Out of scope, stated so nobody builds it

- Editing from the lane dropdown. The drawer's `PlanFilePopup` keeps that; the lane modal is read only.
- Relative images in a plan folder. `PlanFiles` serves markdown names only, so only absolute image URLs render.
  Serving `.plans/<folder>/*.png` would be a new route with its own path-safety rules, and deserves its own plan.
- "Front-end plan" and "back-end plan" entries. No agent or status writes such a file today (`agents/*.md`,
  `status.rb`), so there is nothing to list. Adding a name later is one row in `DOCUMENT_LABELS` and `READABLE`.

## How to test

- Server: `bundle exec rspec spec/openlanes/web/plan_files_spec.rb` passes, including the `pull-requests.md` case (listed last, readable, `ReadOnly` on write).
- Web unit tests: `cd web && npm test` shows 69 files and 648 tests passing; `npm run lint` and `npx tsc --noEmit` print no errors.
- Whole suite and lint: `bundle exec rspec` reports 0 failures and `bundle exec rubocop` reports no offenses.
- By hand: run `openlanes web --demo`, open the board on a wide window. Each of your lanes ends its details block with a "Documents ▾" button; its menu lists Specification first, then Plan, Contract, Research, Design, Blocked and Pull requests, whichever the plan has.
- Choose Specification: a modal opens with the frontmatter as highlighted YAML, then the rendered body. `[x]` top right and the footer Close both close it, as does Esc.
- Put a `> [!NOTE]` blockquote and a ` ```mermaid ` block in a plan's `research.md` and open Research: you see a coloured admonition box and an SVG diagram.
- Narrow the browser below 1200px, 600px and 450px: the modal's margins shrink to 15%, 5% and 1px.
- Turn on "Narrow Lanes", or turn on "All Machines": narrow lanes and other machines' lanes show no Documents button.
- End to end: `just web-e2e` runs `web/cypress/e2e/lane-documents.cy.ts` against the demo server.
