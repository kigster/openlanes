# Decisions: inter-agent-communication

## D1. The unacked count and last-known state travel on the snapshot wire

Asked by frontend-coder, 2026-10-13. Answered by kig, 2026-10-13: option 1.

backend-coder adds `unacked: Integer` and `last_known_state: [...]` to `Live::Snapshot#plan` (`lib/openlanes/live/snapshot.rb`). frontend-coder adds the types (`web/src/api/types.ts`), both JSON fixtures, a `PlanRow` badge and a detail table in `web/src`, with vitest tests. One wire, read-only.

Context: F1 and F2 named a web plan page, view templates and a `web.rb:25` file list that do not exist. The page is the React app in `web/src`, fed by `Live::Snapshot#plan`. Already done by frontend-coder: `contract.md` is served by `GET /api/plans/:ordinal/files/:name` (`lib/openlanes/web/app.rb`, spec in `app_spec.rb`).

## D2. The terminal board carries `unacked` as data only

Asked by frontend-coder, 2026-10-13. Answered by kig, 2026-10-13: yes.

No code paints `Engine::Board` to a terminal here. `unacked` is added to `Board` and its `Row` as data only; the dispatcher (backend-coder's) fills it.

## D3. Legacy plan files stay readable, and the prompts say so

Decided while finishing, 2026-10-14, taking the plan's assumption 5 (no migration).

Folders planned before this change hold `plan-backend.md`, `plan-frontend.md` and `implementation-plan.md`. Routing falls back to `plan-<section>.md` when `plan.md` has no matching `##` section, the builders' ledgers still list their old file, and the backend-coder, frontend-coder and staff-reviewer prompts tell the agent to read the old names as the same documents. So `rg implementation-plan lib agents` is not empty, which the plan's done-when asked for; an empty grep would have stranded every older folder, this one included.

## D4. The builders sign in `plan.md` first

backend-coder and frontend-coder's `ledger:` became `[plan.md, pull-requests.md, plan-<half>.md]`. The harness writes its own lines to the first file, and `plan.md` is where the units now live (chores-coder already signs there). The legacy file stays last so its old signatures are still read.

## D5. A need may name a section: `plan.md#frontend`

`needs:` entries are file names, or `file#section`, meaning the `###` headings under that file's `## Section` (case-insensitive). One frontmatter value, no new key, and the fallback to `plan-<section>.md` is derived rather than listed.

## D6. `openlanes api docs` points at Redocly's CLI, not a hosted Redoc link

A hosted Redoc page loads only a URL it can fetch over HTTP, and a path on this disk is not one. The command prints `npx @redocly/cli build-docs <path> -o <dir>/openapi.html` per file. Problems go to STDERR as `path: reason` and the exit status is 65.

## D7. Where F1 landed on the page

No plan page exists (D1), so the unacked count is a badge in the plan row's meta line and the `last-known-state` table sits in the agent drawer, the only per-plan detail view. The board spec examples went into `spec/openlanes/engine/board/row_spec.rb` rather than a new `unacked_spec.rb`.
