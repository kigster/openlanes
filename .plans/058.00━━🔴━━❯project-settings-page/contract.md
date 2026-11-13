# Contract: 058.00 Project Settings Page

Owner: backend-coder. Machine-readable form: [openapi.yaml](openapi.yaml).

## Baseline

Full suite before any change: see `## Baseline result` at the end (filled in when the run finishes).

## HTTP

All JSON. Both routes are served by `OpenLanes::Web::App`, from the server's project root (`context.root`), which is the main checkout.

### `GET /api/settings`

`200`:

```
{
  "schema":   <the JSON Schema document, Config::Schema.document, commands included>,
  "keys":     ["project", "starts", ...],          // Config::KEYS, top-level order
  "values":   { "jobs": 2, "merge": { "by": "human" }, ... },  // what .openlanes.yml holds, string keys; unset keys absent
  "defaults": { "jobs": null, "merge": { "by": null, "max_rejections": null }, ... }, // Config::Schema.defaults
  "etag":     "<sha256 hex of the file's bytes; sha256 of empty string when no file>",
  "branch":   "main"                                // the main checkout's current branch, null when detached
}
```

Panes (layout is the page's; the data that drives it): a key in `keys` whose schema node has `properties` is a section with its own pane; every other key is a top-level scalar and goes in the first pane. `commands` has one sub-pane per entry in `schema.properties.commands.properties`.

### `PUT /api/settings`

Headers: `X-CSRF-Token` (from `/api/session`), `If-Match: <etag from GET>` (required).
Body: `{ "values": { ... } }`, the whole file as it should be, same shape as GET's `values`. A key that is absent, `null`, `""` or an empty object is unset.

| Status | Body | Meaning |
| :-- | :-- | :-- |
| 200 | `{ "changed": false }` | parses to the same settings as the file; nothing written, no commit |
| 200 | `{ "changed": true, "commit": "<sha>", "etag": "<new etag>" }` | written (`Config#to_yaml`), committed (`.openlanes.yml` alone), pushed to `origin/main` |
| 422 | `{ "errors": [{ "path": ["merge","by"], "message": "..." }] }` | refused by the schema or `Config.parse`; nothing written. `path` is `[]` when the refusal names no key |
| 409 | `{ "refusal": "not_on_main" \| "dirty_config" \| "cannot_fast_forward" \| "stale_etag" \| "push_failed" \| "commit_failed", "reason": "..." }` | an S1 guard; nothing written, HEAD and `origin/main` unmoved (`push_failed`: the local commit is undone; `commit_failed`: the file and index are restored) |
| 428 | `{ "error": "If-Match is required; send the etag from GET" }` | no `If-Match` |
| 500 | `{ "error": "git failed while saving .openlanes.yml; see the server log" }` | any other git failure; the body never carries the checkout path or git output |
| 403 | `{ "error": "X-CSRF-Token does not match; fetch /api/session again" }` | CSRF mismatch |

Order of checks: CSRF, If-Match present, validation (422), then guards (409: `not_on_main`, `dirty_config`, `stale_etag`, `cannot_fast_forward`), then the no-change check, then write/commit/push. The push is declared through `Boundary.sanction` before it runs.

amended: `commit_failed` (409) and 500 added (2026-11-13, round 3, staff-reviewer F2 and security F102) — a failing commit (hook, gpg, index.lock) used to answer 500 with git output and leave the file dirty.
amended: `push_failed` added (2026-11-13) — a push can be refused even after the fast-forward check; the commit is reset so nothing is half-landed.

## File ownership

| Files | Owner |
| :-- | :-- |
| `lib/openlanes/web/settings.rb`, `lib/openlanes/web/settings_save.rb`, `lib/openlanes/web/app.rb` (settings routes), `spec/openlanes/web/settings*_spec.rb` | backend-coder |
| `contract.md`, `openapi.yaml` (this folder) | backend-coder |
| `web/src/api/settings.ts`, `web/src/api/types.ts` (settings types), `web/src/settings/**`, `web/src/shell/{Nav,Pages}.tsx`, `web/src/shell/useRoute.ts`, `web/cypress/e2e/settings.cy.ts`, `web/cypress/support/**` new files | frontend-coder |

No shared file. Cypress's temp-repo setup is frontend-coder's; if it needs a server-side hook, mail backend-coder.

## Build order

B1 (Settings) and B2 (SettingsSave) → B3 (routes). F1 → F2 → F3 → F4 (needs B3).

## Integration proof

`web/cypress/e2e/settings.cy.ts` against the real server rooted in a temp repo whose `origin` is a bare repo: edit `jobs`, save, assert the bare remote's `main` holds the new `.openlanes.yml` and the next `/api/board` reads it. Back-end proof without the browser: `spec/openlanes/web/settings_api_spec.rb` (Rack::Test against a real temp repo with a bare remote, nothing stubbed).

## Baseline result

Full suite started before any change (`bundle exec rspec`, seed 12535): still running when this round's time ran out; one `F` seen in its progress output at that point, in a file this plan does not touch. Settings specs after the change: `bundle exec rspec spec/openlanes/web/settings*_spec.rb` → 31 examples, 0 failures. `bundle exec rubocop` → 998 files, no offenses.

amended: settings root (2026-11-13) — the routes read and write `.openlanes.yml` in the server's project root (`context.root`, the directory `openlanes web` runs in), not the parent of `--dir`. An e2e run must start the server from its temp project; `bin/web-e2e` now does.

Round 2 suite: `bundle exec rspec` → 6675 examples; the one failure was `docs/architecture` gone stale with the new classes, regenerated with `just update-architecture`, now 0 failures. The round 1 baseline run never finished.
