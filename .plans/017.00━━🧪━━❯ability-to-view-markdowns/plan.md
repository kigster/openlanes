# Plan 017.00: view and edit a blocked plan's markdown files

One pull request, seven units: three back end, four front end. The contract is three routes and one hash.

## Settled here

The spec left these open and said none blocks the split. The plan fixes them so both halves build against one contract; luke-backend writes them into `contract.md` first.

1. **Hash transport.** `GET /api/plans/:ordinal/files/:name` answers with `ETag: "<sha256 hex of the raw bytes>"`. `PUT` sends it back as `If-Match`. Strong ETag, quoted.
1. **Whole file on save.** The client sends the whole file as `text/markdown`. The server compares the frontmatter block byte for byte against the file on disk; a difference is refused. A file with no frontmatter on disk refuses a body that adds one.
1. **Live car.** A plan has a live car when `Live.board(store:, keys:)` lists the ordinal under `me.plans` with a non-empty `cars` array. That is the same data the page draws cars from, so the UI and the server cannot disagree.
1. **Status codes for `PUT`.** `403` bad or missing CSRF. `403` with `error: "<name> is read only"` for a readable but non-editable name (`blocked.md`). `404` not a plan file, not a plan number, no such plan, no such file. `428` missing `If-Match`. `412` `If-Match` does not match the file. `409` live car. `422` frontmatter changed. `200` with the new `ETag` on success.
1. **Empty folder.** The listing route returns `{"files": []}`; the drawer shows "No markdown files in this plan".

## Order and dependency graph

```mermaid
flowchart LR
  B1[B1 PlanFiles] --> B2[B2 routes + contract]
  B2 --> B3[B3 demo plans fixture]
  B2 -. contract.md .-> F1[F1 API client]
  F1 --> F2[F2 popup]
  F2 --> F3[F3 drawer + wiring]
  B3 --> F4[F4 integration]
  F3 --> F4
```

- B1, then B2, then B3: sequential, and B2 lands `contract.md` before F1 starts.
- F1, F2, F3 are sequential on the front end. F1 starts as soon as `contract.md` exists; it does not wait for B2's code.
- B3 and F1 to F3 run at the same time; they share no file.
- F4 is last and is the integration check.

## Backend

### B1 PlanFiles: list, read, write with guards

- **Discipline:** back end.
- **Owns:** `lib/openlanes/web/plan_files.rb`, `spec/openlanes/web/plan_files_spec.rb`.
- **Must not touch:** `lib/openlanes/web/app.rb`, anything under `web/`.
- **Depends on:** nothing.
- **Shape:** `Web::PlanFiles` holds the whitelist that today is `App::PLAN_FILES` (moved here in B2, not copied) plus `EDITABLE = %w[spec.md plan.md]`. `PlanFiles.new(plans_dir:)` with `list(ordinal) -> Array<String>` (whitelist order, existing files only), `read(ordinal, name) -> Data(body:, etag:)`, `write(ordinal, name, body:, if_match:) -> String` (the new etag). Raises `NotFound`, `ReadOnly`, `Stale`, `FrontmatterChanged`. Splitting frontmatter reuses `OpenLanes::Frontmatter`; no second parser. The write is atomic (temp file in the same folder, then rename). It knows nothing of HTTP or cars.
- **Done when:** `spec/openlanes/web/plan_files_spec.rb` passes, on real `.plans` trees through `PlansFixture`: list with some, none and all six files; read returns the SHA-256 etag; write succeeds and returns the new etag; stale hash refused and the file unchanged; changed frontmatter refused in `spec.md`; frontmatter added to a `plan.md` that had none refused; `blocked.md` refused as read only; an unknown ordinal is `NotFound`.

### B2 Routes, live-car refusal, contract

- **Discipline:** back end.
- **Owns:** `lib/openlanes/web/app.rb`, `spec/openlanes/web/app_spec.rb`, and in the plan folder `contract.md` and `openapi.yaml`.
- **Must not touch:** `lib/openlanes/web/plan_files.rb` (B1's, finished before B2 starts), anything under `web/`.
- **Depends on:** B1.
- **Shape:**
  - `GET /api/plans/:ordinal/files` → `200 {"files": ["spec.md", ...]}`, `404` for an unknown ordinal.
  - `GET /api/plans/:ordinal/files/:name` → unchanged body and `text/markdown`, plus `ETag`.
  - `PUT /api/plans/:ordinal/files/:name` → CSRF as at `app.rb:167-168`, then the codes under "Settled here", item 4. The live-car check reads `Live.board(store:, keys: context.keys)` before calling `PlanFiles#write`.
  - `App::PLAN_FILES` goes; the routes read `PlanFiles`. The comment at `app.rb:14-16` changes to say the page may read six files and write two.
- **Done when:** `spec/openlanes/web/app_spec.rb` passes with new examples beside `:414-463`: listing (some, none, unknown ordinal); `ETag` on GET; PUT success and a following GET returning the new body and ETag; missing CSRF; `blocked.md`; traversal (`..%2Fspec.md`); missing `If-Match`; stale `If-Match`; changed frontmatter; a live car in the store refused with `409` and the file unchanged. `contract.md` and `openapi.yaml` exist and `openlanes api docs` lists the latter. `just lint` and `just test` green.

### B3 Demo plans fixture for the browser

- **Discipline:** back end.
- **Owns:** `web/cypress/fixtures/plans/` (a `.plans` tree: one folder for each blocked plan in `web/src/api/fixtures/board.json`, at least one with no car, holding `spec.md` with frontmatter, `plan.md` and `blocked.md`), and `bin/web-e2e` (copy that tree to a temp dir and pass it as `--dir` to the demo servers, so a save never dirties the checkout).
- **Must not touch:** `web/src/api/fixtures/board.json`, `lib/openlanes/web/app.rb`, `web/cypress/e2e/`.
- **Depends on:** B2.
- **Done when:** `just web-e2e` still passes the existing `web/cypress/e2e/*.cy.ts` with the new `--dir`, and `GET /api/plans/<ordinal>/files` against the demo server lists the fixture's files.

## Frontend

### F1 API client for plan files

- **Discipline:** front end.
- **Owns:** `web/src/api/planFiles.ts`, `web/src/api/planFiles.test.ts`, the `PlanFile` type in `web/src/api/types.ts`.
- **Must not touch:** `web/src/api/client.ts` beyond importing from it, any `lib/` file.
- **Depends on:** B2's `contract.md` (the document, not the code).
- **Shape:** `listPlanFiles(ordinal) -> Promise<string[]>`, `readPlanFile(ordinal, name) -> Promise<{ body, etag }>`, `savePlanFile(ordinal, name, body, etag, csrf) -> Promise<{ etag }>`, which throws a typed `PlanFileError` carrying the status and the server's `error`, so the popup can name a conflict.
- **Done when:** `web/src/api/planFiles.test.ts` passes: the URLs, the `If-Match` and `X-CSRF-Token` headers sent, and each refusal status mapped to `PlanFileError`.

### F2 The single preview popup with Edit

- **Discipline:** front end.
- **Owns:** `web/src/panels/PlanFilePopup.tsx`, `web/src/panels/PlanFilePopup.test.tsx`, `web/src/panels/planFile.ts` (split a file into frontmatter and body, and join them back).
- **Must not touch:** `MarkdownEditor.tsx`, `markdown.ts`, `dialogs.tsx` (used, not changed), `App.tsx`.
- **Depends on:** F1.
- **Shape:** one Radix dialog from `dialogs.tsx`. Props: `ordinal`, `name`, `editable: boolean` (false for any name outside `spec.md`/`plan.md`, and false while the plan has a live car), `onClose`. Renders through `markdown.ts`. Edit swaps in `MarkdownEditor` over the body; the frontmatter sits above it, read only. Save joins the untouched frontmatter to the edited body and sends the ETag it read; a `412` or `409` shows the reason and keeps the text.
- **Done when:** `web/src/panels/PlanFilePopup.test.tsx` passes: renders markdown; no Edit button for `blocked.md`; Edit disabled with a live car; the request body's frontmatter is byte-equal to what was read after the user types in the body; a `412` shows a conflict message; the close button and Esc close it.

### F3 Plan drawer opened by the red pill

- **Discipline:** front end.
- **Owns:** `web/src/panels/PlanDrawer.tsx`, `web/src/panels/PlanDrawer.test.tsx`, `web/src/panels/index.ts` (export), `web/src/panels/panels.css`, `web/src/App.tsx`, `web/src/App.test.tsx`.
- **Must not touch:** `AgentDrawer.tsx`, `UnblockWidget.tsx`, `StatusBar.tsx` (the pill already calls `onToggleUnblock`), any `lib/` file.
- **Depends on:** F2.
- **Shape:** `onToggleUnblock` in `App.tsx` opens `PlanDrawer` for the same ordinal beside `UnblockWidget`, and closes both together. The drawer puts `listPlanFiles` in a dropdown, with an empty state when there are none; choosing a name mounts the one `PlanFilePopup` with that name, and choosing another replaces it. `editable` comes from the plan's `cars` on the board.
- **Done when:** `web/src/panels/PlanDrawer.test.tsx` and `web/src/App.test.tsx` pass: the pill on a plan with no car opens the drawer; the dropdown holds exactly the listed names; the empty state; choosing two files in turn leaves one popup holding the second. `just web-test` (lint, typecheck, coverage) is green.

### F4 Integration check: red pill to saved file

- **Discipline:** front end.
- **Owns:** `web/cypress/e2e/plan-files.cy.ts`.
- **Must not touch:** every other file.
- **Depends on:** B3, F3.
- **What it must show,** against the real `openlanes web --demo` server and B3's plans tree, nothing stubbed or intercepted: click the red pill of a blocked plan with no car; the drawer lists the fixture's files; open `blocked.md`, rendered, with no Edit; open `spec.md`, and the popup is replaced, not doubled; Edit, change the body, Save; reopen `spec.md` and see the change read back from the server; the frontmatter on disk is unchanged (`cy.readFile`); a save after the file was rewritten on disk behind the popup (`cy.writeFile`) shows the conflict message.
- **Done when:** `just web-e2e` passes `web/cypress/e2e/plan-files.cy.ts`.

## HTTP surface

Yes. One new route (`GET /api/plans/:ordinal/files`), one new header on an existing route (`ETag` on `GET /api/plans/:ordinal/files/:name`), and one new write route (`PUT /api/plans/:ordinal/files/:name`). luke-backend writes `openapi.yaml` beside `contract.md`, and `openlanes api docs` lists it.

## Notes for the builders

- `web/node_modules` was absent during research, so the web suite has no known baseline. rey-frontend runs `just web-install` and `just web-test` before F1 and records the result in the ledger.
- A web save leaves the tree dirty. That is intended: the harness owns commits (spec, Out of scope).

## Rebase decisions

Replaying 547d0a2 onto `origin/main` 0b10d65, 2026-10-17, bb8-resolver.

- `plan.md`: kept the branch's copy. It is main's copy plus the `## How to test` section added this round, and nothing in it was removed.
- `pull-requests.md`: kept the branch's copy. It is main's copy plus the 2026-10-17 backend and frontend proofs, and nothing in it was removed.
- `state.json`: kept the branch's copy. Every stage, signature and message on main is in it unchanged. It adds 3 stages, 6 signatures, mail #14 to #17 and a later `updated_at`, and marks mail #13 read.
- `lib/openlanes/apps/probe.rb`: kept main's `listening?` (the block form of `Socket.tcp`, with main's comment) and dropped the branch's version (`ensure socket&.close`). Both are the same fix, `remote_address` on the socket, and main's `probe_spec.rb` stubs `Socket.tcp` with `and_yield`, which only works with the block form. The branch's macOS 27 finding is still recorded in `pull-requests.md`.
- `spec/fixtures/apps/servers/server.rb`: kept main's `Socket.tcp(..., &:remote_address)`. The branch's `.tap(&:remote_address).close` is the same fix, and the block form also closes the socket when `remote_address` raises.
- `lib/openlanes/web/app.rb`: removed `PLAN_FILES`, as the branch did (B2 moved it to `PlanFiles::READABLE`, and nothing else on main reads it). Kept main's `LOCAL_HOSTS` comment, which names `Listen#permitted_hosts`.
- `spec/spec_helper.rb`: kept main's four new requires and `TestRedis.scrub!`, and added the branch's `require_relative "support/port_window"` next to them.
- `web/src/App.tsx`: kept main's `data-lanes={lanes.lanes}` on `<main>`, with the branch's `<PlanDrawer plan={unblockPlan} />` just before it and after main's `BombNotice` and `UnblockWidget`.
- `web/src/panels/index.ts`: kept every export from both sides: main's `BombNotice`, and the branch's `PlanDrawer` and `PlanFilePopup`.

## How to test

From the repository root, Ruby 4.0 under rbenv (`eval "$(rbenv init -)"`).

- `bundle exec rspec spec/openlanes/web/plan_files_spec.rb spec/openlanes/web/app_spec.rb`: 0 failures. Covers B1 (list, read, ETag, atomic write, stale hash, locked frontmatter, read-only `blocked.md`, unknown plan) and B2 (the three routes and every refusal: `403` CSRF, `403` read only, `404` traversal, `428`, `412`, `422`, `409` live car).
- `bundle exec rspec` and `bundle exec rubocop`: both exit 0.
- `just web-install`, then `just web-test`: lint and typecheck clean, vitest green (F1 client, F2 popup, F3 drawer and App wiring).
- `just web-build`, then `just web-e2e`: Cypress prints `All specs passed!`, `plan-files.cy.ts` 2/2 (F4, against the real demo server and B3's fixture). If another session holds port 11100, set free ports: `E2E_PORT=11890 E2E_PEER_PORT=11891 just web-e2e`.
- After `just web-e2e`, `git status web/cypress/fixtures` shows no change: saves went to a temp copy.
- By hand: `tmp=$(mktemp -d) && cp -R web/cypress/fixtures/plans/. "$tmp"`, then `just web-demo --dir "$tmp"` and open `http://127.0.0.1:11000` (add `--port N` and use that port below if 11000 is taken).
  - Click the red pill of `002.00` (blocked, no car): the plan drawer opens beside the unblock widget, and its dropdown lists `spec.md`, `plan.md`, `blocked.md`.
  - Choose `blocked.md`: it renders as markdown, with no Edit button.
  - Choose `spec.md`: the one popup now shows `spec.md`, not a second popup. Edit, change the body, Save, reopen: the change is there, and `head -4 "$tmp"/002*/spec.md` shows the frontmatter unchanged.
  - With the popup open, change the file on disk, then Save: the popup names the conflict and keeps the typed text.
  - `001.00` (blocked, two cars): Edit is disabled.
  - `curl -s http://127.0.0.1:11000/api/plans/002/files` prints `{"files":["spec.md","plan.md","blocked.md"]}`; `curl -si http://127.0.0.1:11000/api/plans/002/files/spec.md | rg -i etag` prints a quoted 64-hex `ETag`; a `curl -X PUT` to the same URL without `X-CSRF-Token` answers `403`.

> [!NOTE]
>
> [2026-10-15 09:47:08 AM PDT] [ agent: luke-backend   status: **Interrupted, round 1 (harness died)** ]

> [!NOTE]
>
> [2026-10-15 09:47:08 AM PDT] [ agent: rey-frontend   status: **Interrupted, round 1 (harness died)** ]

> [!NOTE]
>
> [2026-10-15 09:59:26 AM PDT] [ agent: luke-backend   status: **Interrupted, round 1 (harness died)** ]

> [!NOTE]
>
> [2026-10-15 09:59:26 AM PDT] [ agent: rey-frontend   status: **Interrupted, round 1 (harness died)** ]

> [!NOTE]
>
> [2026-10-15 10:10:58 AM PDT] [ agent: luke-backend   status: **Interrupted, round 1 (harness died)** ]

> [!NOTE]
>
> [2026-10-15 10:10:58 AM PDT] [ agent: rey-frontend   status: **Interrupted, round 1 (harness died)** ]

> [!NOTE]
>
> [2026-10-15 07:54:45 PM PDT] [ agent: luke-backend   status: **Interrupted, round 1 (harness died)** ]

> [!NOTE]
>
> [2026-10-15 07:54:45 PM PDT] [ agent: rey-frontend   status: **Interrupted, round 1 (harness died)** ]
