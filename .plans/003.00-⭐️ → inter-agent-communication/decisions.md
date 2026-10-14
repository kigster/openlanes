# Decisions: inter-agent-communication

## D1. The unacked count and last-known state travel on the snapshot wire

Asked by rey-frontend, 2026-10-13. Answered by kig, 2026-10-13: option 1.

luke-backend adds `unacked: Integer` and `last_known_state: [...]` to `Live::Snapshot#plan` (`lib/openlanes/live/snapshot.rb`). rey-frontend adds the types (`web/src/api/types.ts`), both JSON fixtures, a `PlanRow` badge and a detail table in `web/src`, with vitest tests. One wire, read-only.

Context: F1 and F2 named a web plan page, view templates and a `web.rb:25` file list that do not exist. The page is the React app in `web/src`, fed by `Live::Snapshot#plan`. Already done by rey: `contract.md` is served by `GET /api/plans/:ordinal/files/:name` (`lib/openlanes/web/app.rb`, spec in `app_spec.rb`).

## D2. The terminal board carries `unacked` as data only

Asked by rey-frontend, 2026-10-13. Answered by kig, 2026-10-13: yes.

No code paints `Engine::Board` to a terminal here. `unacked` is added to `Board` and its `Row` as data only; the dispatcher (luke-backend's) fills it.
