---
execution: concurrent
---

Not a refactor (no `implementation_requirement: refactor`; it adds a page and an endpoint). About 15 files and a few hundred lines, both far under the 50% threshold (`refactor.threshold` unset).

# Plan 058.00: Project Settings Page

## Order and dependency graph

```
B1 Settings model ──┐
                    ├─> B3 HTTP routes + openapi ─┐
B2 Settings save ───┘                             ├─> F4 Cypress (integration check)
F1 API client ──> F2 Settings page ──> F3 Nav + route ┘
```

- B1 and B2 run in parallel (separate files). B3 waits for both.
- F1 needs only the response shapes below, so it starts beside B1/B2. F2 needs F1; F3 needs F2.
- F4 needs B3 and F3. It is the integration check.

Both depended-on plans are merged: 056 gave the nav (`web/src/shell/Nav.tsx` carries a "Plan 058 adds" placeholder) and path routing (`useRoute.ts`, `Pages.tsx`); 057 gave `Config::Schema` (`lib/openlanes/support/config/schema.rb`, `schemas/openlanes-config.schema.json`), `Config#to_yaml` (the full-file writer) and the main-checkout lookup in `lib/openlanes/vcs*`.

Decision: the save is a dedicated synchronous `PUT /api/settings`, not a `POST /api/commands` entry. `Live::Commands` only runs inside a live dispatcher, so with no run going a save would never land, and a refused field has to come back on the same request. `PUT /api/plans/:ordinal/files/:name` is the precedent.

## HTTP surface

Yes. `backend-coder` writes `openapi.yaml` beside `contract.md` in this plan folder.

- `GET /api/settings` → `200 { schema: <JSON Schema document>, keys: [..Config::KEYS order..], values: {..}, defaults: {..}, etag: "<sha of .openlanes.yml>", branch: "main" }`
- `PUT /api/settings` with header `X-CSRF-Token`, `If-Match: <etag>`, body `{ values: {..} }` →
  - `200 { changed: false }`: nothing differs, nothing written.
  - `200 { changed: true, commit: "<sha>", etag: "<new>" }`: written, committed, pushed.
  - `422 { errors: [{ path: ["merge","by"], message: ".." }] }`: `Config.parse` / schema refused; nothing written.
  - `409 { refusal: "not_on_main" | "dirty_config" | "cannot_fast_forward" | "stale_etag", reason: ".." }`: S1 guards; nothing written.
  - `403` on a CSRF mismatch, as every other write.

## Backend

### B1 Settings model (read and validate)

- **Discipline:** back end
- **Owns:** `lib/openlanes/web/settings.rb`, `spec/openlanes/web/settings_spec.rb`
- **Must not touch:** `lib/openlanes/web/app.rb`, `lib/openlanes/web/settings_save.rb`, `web/**`
- **Depends on:** nothing
- **Done when:** `spec/openlanes/web/settings_spec.rb` passes. `OpenLanes::Web::Settings` with `read(root) -> Data(schema, keys, values, defaults, etag)` and `validate(values) -> [errors]`. Each error names its key path, drawn from `Config::Schema.errors` plus `Config.parse`. Panes follow `Config::KEYS`: scalar keys first, then one pane per section, `commands:` with one sub-pane per command from `commands_schema.rb`.

### B2 Settings save (guards, write, commit, sanctioned push)

- **Discipline:** back end
- **Owns:** `lib/openlanes/web/settings_save.rb`, `spec/openlanes/web/settings_save_spec.rb`
- **Must not touch:** `lib/openlanes/web/app.rb`, `lib/openlanes/web/settings.rb`, `lib/openlanes/execution/boundary.rb` (calls `Boundary.sanction`, does not change it)
- **Depends on:** nothing (calls B1's `validate` through its public signature; the spec uses a real temp repo with a bare remote, no stubs)
- **Done when:** `spec/openlanes/web/settings_save_spec.rb` passes against a real temp repo plus a bare `origin`. It covers: no change writes nothing and makes no commit; a change writes `Config#to_yaml` output, commits `.openlanes.yml` alone, and declares the push through `Boundary.sanction` before pushing `main`; each refusal (not on `main`, uncommitted `.openlanes.yml` edits, `main` cannot fast-forward to `origin/main`, stale etag) returns its reason and leaves the file, HEAD and `origin/main` untouched; an invalid value is refused before any write.

### B3 HTTP routes and contract

- **Discipline:** back end
- **Owns:** `lib/openlanes/web/app.rb` (the two `/api/settings` routes only), `spec/openlanes/web/settings_api_spec.rb`, `openapi.yaml` and `contract.md` in this plan folder
- **Must not touch:** `lib/openlanes/web/settings.rb`, `lib/openlanes/web/settings_save.rb`, `web/**`
- **Depends on:** B1, B2
- **Done when:** `spec/openlanes/web/settings_api_spec.rb` (Rack::Test) shows GET's shape; PUT returns 200 unchanged, 200 changed, 422 with field paths, 409 for each refusal, 403 without CSRF. `openlanes api docs` lists `openapi.yaml`. `just lint` stays at zero offenses.

## Frontend

### F1 Settings API client

- **Discipline:** front end
- **Owns:** `web/src/api/settings.ts`, `web/src/api/settings.test.ts`, the settings types in `web/src/api/types.ts`
- **Must not touch:** `web/src/settings/**`, `web/src/shell/**`
- **Depends on:** nothing (codes to the shapes under HTTP surface)
- **Done when:** `web/src/api/settings.test.ts` passes: `useSettings()` query and `useSaveSettings()` mutation, with CSRF and `If-Match` headers sent and 422/409 bodies surfaced as typed errors.

### F2 Settings page, form and panes

- **Discipline:** front end
- **Owns:** `web/src/settings/**` (`SettingsPage.tsx`, `Pane.tsx`, `Field.tsx`, `settings.css`, their `*.test.tsx`)
- **Must not touch:** `web/src/api/**`, `web/src/shell/**`
- **Depends on:** F1
- **Done when:** `web/src/settings/SettingsPage.test.tsx`, `Pane.test.tsx` and `Field.test.tsx` pass. They show: every schema key rendered with value or default and its help line; field type from schema (text, number, toggle, select for enums); first pane holds top-level scalars, then one pane per section in `keys` order, `commands` with one sub-pane per command; all panes open on load, −/+ collapses and opens; a 422 error shown on its field; a 409 reason shown beside the button; button reads **Save, commit and push to main** with the note beside it; a save with nothing changed sends nothing.

### F3 Nav entry and `/settings` route

- **Discipline:** front end
- **Owns:** `web/src/shell/Nav.tsx`, `web/src/shell/Pages.tsx`, `web/src/shell/useRoute.ts`, and their tests (`Nav.test.tsx`, `useRoute.test.ts`)
- **Must not touch:** `web/src/settings/**`, `web/src/api/**`
- **Depends on:** F2
- **Done when:** `Nav.test.tsx` shows `Board | Plan dependencies | Project settings` and `useRoute.test.ts` resolves `/settings`; `Pages.tsx` mounts `SettingsPage` there.

### F4 Cypress end-to-end (integration check)

- **Discipline:** front end
- **Owns:** `web/cypress/e2e/settings.cy.ts`, any temp-repo setup task it needs under `web/cypress/support/` or `web/scripts/` (new files only)
- **Must not touch:** files owned by B1-B3, F1-F3
- **Depends on:** B3, F3
- **Done when:** `web/cypress/e2e/settings.cy.ts` passes against the real server, nothing stubbed, rooted in a temp repo whose `origin` is a bare repo. It must show: `/settings` lists every key with each pane open; −/+ collapses a pane; a refused value shows on its field and the file is unchanged; saving with no change makes no commit; editing `jobs` and saving moves the bare remote's `main` to a commit whose `.openlanes.yml` holds the new value, and the next `/api/board` snapshot reads it; making `.openlanes.yml` dirty in the temp repo shows the refusal reason.

## Task completed when

- The page lists every key in the schema, each pane open, each collapsible with −/+.
- A refused value is shown on its field and nothing is written.
- Save with no change writes nothing; with a change it writes, commits and pushes `main`, and the board's next snapshot reads the new value.
- Each refusal in S1's constraints is shown with its reason.
- Component tests for the form and the panes; a Cypress test that edits a value and saves against a temp repo with a bare remote.

## How to test

- The page lists every key in the schema, each pane open, each collapsible with −/+.
- A refused value is shown on its field and nothing is written.
- Save with no change writes nothing; with a change it writes, commits and pushes `main`, and the board's next snapshot reads the new value.
- Each refusal in S1's constraints is shown with its reason.
- Component tests for the form and the panes; a Cypress test that edits a value and saves against a temp repo with a bare remote.
