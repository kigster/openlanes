# Contract 017.00: plan files, read and write

Owner: luke-backend. Consumer: rey-frontend. The machine-readable form is [`openapi.yaml`](openapi.yaml), beside this file.

## Baseline

- Ruby suite (`bundle exec rspec`) before any change: 3013 examples, 0 failures, 9 pending. No baseline failures.
- Web suite: rey-frontend records it (plan.md, Notes for the builders).

## Names

- **Readable** (whitelist order, the order the listing returns): `spec.md`, `plan.md`, `contract.md`, `blocked.md`, `research.md`, `design.md`.
- **Editable:** `spec.md`, `plan.md`. Every other readable name is read only.
- `:ordinal` is a plan number: `017`, `017.00` both parse. Anything else is `404 {"error": "not a plan number"}`.

Every error body is JSON: `{"error": "<sentence>"}`.

## 1. `GET /api/plans/:ordinal/files`

- `200 application/json` → `{"files": ["spec.md", "plan.md", "blocked.md"]}`: readable names that exist in the folder, in whitelist order. A folder with none → `{"files": []}`.
- `404` → `not a plan number` | `there is no plan 017.00`.

## 2. `GET /api/plans/:ordinal/files/:name`

- `200 text/markdown;charset=utf-8`, body is the file's raw bytes, unchanged.
- Header `ETag: "<sha256 hex of the raw bytes>"`: strong, quoted, 64 lowercase hex characters inside the quotes.
- `404` → `not a plan file: <name>` | `not a plan number` | `there is no plan <ordinal>` | `<ordinal> has no <name>`.

## 3. `PUT /api/plans/:ordinal/files/:name`

Request:

- Header `X-CSRF-Token: <csrf from GET /api/session>`.
- Header `If-Match: "<etag from the GET>"`, sent back exactly as received (quoted).
- Header `Content-Type: text/markdown`.
- Body: the **whole file**, frontmatter included. The frontmatter block (`---\n...\n---\n` at the very start) must be byte-equal to the one on disk. A file with no frontmatter on disk must stay without one.

Responses, checked in this order (the first that applies wins):

| Status | When | `error` |
| :--- | :--- | :--- |
| `403` | missing or wrong `X-CSRF-Token` | `X-CSRF-Token does not match; fetch /api/session again` |
| `404` | name not readable, not a plan number, no such plan, no such file | as in route 2 |
| `403` | readable but not editable (`blocked.md`, …) | `<name> is read only` |
| `428` | no `If-Match` header | `If-Match is required; send the ETag from GET` |
| `409` | the plan has a live car | `<ordinal> has an agent working on it; wait until it stops` |
| `412` | `If-Match` is not the file's current ETag | `<name> changed since it was read; reload it` |
| `422` | the frontmatter block differs from disk, or was added/removed | `the frontmatter of <name> is locked` |
| `200` | written | body `{"etag": "\"<sha256>\""}`, and the same value in the `ETag` header |

The write is atomic (temp file in the plan folder, then rename). Nothing is written on any refusal.

### Live car

A plan has a live car when `GET /api/board` has, under `me.plans`, an entry whose `ordinal` equals the plan number and whose `cars` array is non-empty. The UI disables Edit on exactly that rule; the server refuses with `409` on exactly that rule. With no snapshot in the store (`me` is `null`), no plan has a live car.

## File ownership

| Files | Owner |
| :--- | :--- |
| `lib/openlanes/web/plan_files.rb`, `lib/openlanes/web/app.rb`, `spec/openlanes/web/plan_files_spec.rb`, `spec/openlanes/web/app_spec.rb` | luke-backend |
| `web/cypress/fixtures/plans/`, `bin/web-e2e` | luke-backend (B3) |
| `contract.md`, `openapi.yaml` | luke-backend |
| `web/src/**`, `web/cypress/e2e/plan-files.cy.ts` | rey-frontend |

No file is shared. `justfile`'s `web-e2e` recipe, if B3 needs to touch it, is luke-backend's and rey is mailed first.

## Build order

1. B1 `PlanFiles` → B2 routes (this contract) → B3 demo plans fixture.
1. F1 starts from this document, not from B2's code. F1 → F2 → F3.
1. F4 last, after B3 and F3.

## Integration proof

`web/cypress/e2e/plan-files.cy.ts` (F4), run by `just web-e2e` against the real `openlanes web --demo` server with B3's plans tree copied to a temp dir: nothing stubbed or intercepted. Red pill → drawer lists the files → `blocked.md` has no Edit → `spec.md` edited and saved → reopened and read back → frontmatter on disk unchanged → a save after a `cy.writeFile` behind the popup shows the `412` conflict.

## Demo plans fixture (B3)

- `web/cypress/fixtures/plans/` holds `001.00━━⭕━━❯clean-agent-boundaries` (blocked in `board.json`, 2 cars) and `002.00━━⭕━━❯fixture-without-a-car`, each with `spec.md` (frontmatter `created`, `lane`), `plan.md` (none) and `blocked.md`.
- `bin/web-e2e` copies that tree to a temp dir, passes it as `--dir` to both demo servers, and gives Cypress its path as `Cypress.env("plansDir")`, so F4 reads a file back with `cy.readFile` under that path.
- Gap for F4: `web/src/api/fixtures/board.json` has one blocked plan, `001.00`, and it has cars, so its Edit is disabled. No blocked plan on the demo board has no car, and B3 may not touch `board.json`. F4 needs a carless blocked plan on the board (for example `002.00` added to `board.json`), which is rey's file.

## Amendments

- amended: Cypress env is `plansDir`, not `plans`, at rey's request (mail #4).
- amended: assumption for the F4 gap: rey adds `002.00` (status `blocked`, one question, `cars: []`) to `web/src/api/fixtures/board.json`; its folder is already in the B3 fixture. B3 is barred from `board.json`.
