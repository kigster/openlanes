# Implementation plan, 012.00 (contract between backend-coder and frontend-coder)

## Baseline

`bundle exec rspec` before any change (2026-10-14 11:47): `2214 examples, 0 failures`, coverage 98.63%. No baseline failures. `web/`: `npx vitest run` green before F1.

## Interfaces frontend-coder calls

### Event stream (`GET /api/events`)

| Event | Data | When |
| --- | --- | --- |
| `apps` | `{ "apps": [<app>, ...] }` | On stream open, only when at least one app runs. The page sets its apps to `[]` on every open first. |
| `app` | `<app>` | Each process whose status changed since the last tick (250 ms). A process whose plan vanished from the listing is sent once with `"state": "stopped"`. |

`<app>` is `Apps::Status#to_h`, copied into `web/src/api/types.ts` as `AppStatus`:

```
{ "plan": "012.00", "branch": "kig/012.00-...", "process": "web",
  "state": "starting|ready|restarting|stopped|failed",
  "port": 11101, "preview": true, "url": "http://127.0.0.1:11101/",
  "framing": "frame|window|null", "reason": "string|null", "at": "ISO-8601" }
```

- `url` is always the process's root, never its `ready:` path.
- `framing` is set only on the preview process, once ready; re-checked after each of its restarts.

### `POST /api/apps/commands`

Header `X-CSRF-Token`. Body `{ "plan": "012.00", "action": "restart" | "stop", "target": "backend" | "<process>" | null }`.

| Status | Body | Why |
| --- | --- | --- |
| 202 | `{ plan, action, target }` with `plan` canonical | queued on `openlanes:<repo>:apps:<node id>:commands` |
| 422 | `{ "error": "plan must be a plan number like 012.00" }` / `"action must be one of restart, stop"` / `"target must be backend or a process name"` | nothing queued |
| 403 | `{ "error": "X-CSRF-Token does not match; ..." }` | nothing queued |

A `restart` with no target restarts every process; `backend` every process but the previewed one, in declared order.

## File ownership

| Files | Owner |
| --- | --- |
| `lib/openlanes/apps.rb`, `lib/openlanes/apps/*`, `lib/openlanes/support/config.rb`, `lib/openlanes/live/keys.rb`, `lib/openlanes/web/events.rb`, `lib/openlanes/web/app.rb` (the route), `lib/openlanes/cli/app/**`, `lib/openlanes/cli.rb`, `lib/openlanes.rb` (loader lines), their specs, `spec/fixtures/apps/servers/` | backend-coder |
| `web/src/**` (preview, api types, events, client, useBoard, App) | frontend-coder |
| `web/cypress/preview/`, `web/cypress.preview.config.ts`, `web/cypress/tsconfig.json`, `spec/fixtures/apps/preview_project/`, `justfile` (`preview-e2e`) | frontend-coder (F2) |
| `docs/USAGE.md` (the `openlanes app` section) | backend-coder |

Shared: none written by both.

## Build order

B1 ‖ B2 ‖ B3 → B4 → B5 → B6; F1 after B1; F2 last.

## Integration proof

`just web-build && just preview-e2e`: a real `openlanes web --demo` on 11050 (Redis database 13) and, started by the spec's tasks, a real `openlanes app start --demo` on `spec/fixtures/apps/preview_project`. Nothing is intercepted. It shows the three checks in `plan.md`.

## Amendments

- amended: `Supervisor#restart` landed with B4 rather than B5; B5 added the watcher and the restart specs. Why: `restart` is `halt` plus `bring_up`, both B4's.
- amended: the Cypress spec lives in `web/cypress/preview/`, not `web/cypress/e2e/`. Why: the demo suite's `cypress.config.ts` runs everything under `e2e/` against port 11000.
- amended: `app status` prints the registry (plan, process, port, pid, checkout), not readiness. Why: it answers without Redis, and readiness is in the Preview tab.
- amended: the server sends `apps` only when non-empty, and the page resets on every open. Why: item 13, a project without `app:` gets the exact stream it had.

## Assumptions

- `openlanes app start` reads `app:` from the checkout it runs in (the plan's worktree when one exists), since backend-coder writes it on the plan's branch first (M12).
- A runner killed with KILL leaves its processes running; its ports are reclaimed by the registry (dead owner) and its board entry expires after 30 s. TERM and INT stop everything.
