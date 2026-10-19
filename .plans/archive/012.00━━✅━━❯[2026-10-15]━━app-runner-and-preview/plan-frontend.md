
# 012.00 App Runner and Preview, front end

`rey-frontend` builds these, against the `apps` / `app` event shape fixed in `plan-backend.md` B1 and the `POST /api/apps/commands` route in B6. F1 needs only B1's shape to start.

## F1 Preview tab

- **Discipline:** front end
- **Covers spec items:** 10, 11 (opening the window), 13 (no tab without an app)
- **Owns:** `web/src/preview/` (`PreviewTab.tsx`, `PreviewToolbar.tsx`, `useApps.ts`, `model.ts`, `preview.css`, and their tests), `web/src/api/types.ts` (`AppStatus`, `AppCommand`, copied from B1 and B6), `web/src/api/events.ts` and `web/src/api/events.test.ts` (handle `apps` and `app`), `web/src/api/client.ts` and `client.test.ts` (`postAppCommand`), `web/src/api/useBoard.ts` (hand `apps` / `app` to the apps cache), `web/src/App.tsx` (one tab per running app, beside Board and Logs)
- **Must not touch:** anything under `lib/` or `spec/`, `web/cypress/`, `web/cypress.config.ts`
- **Depends on:** B1
- **Done when:** `web/src/preview/PreviewTab.test.tsx` shows the label `▶ <plan> · <branch> · :<port>`, an iframe on `url` when `framing` is `frame`, and no iframe but an Open in new window button calling `window.open(url)` when `framing` is `window`; `web/src/preview/PreviewToolbar.test.tsx` shows ● running for `ready`, restarting for `starting`/`restarting`, the reason for `failed`, and Restart backend, Open in new window and Stop posting `{action: "restart", target: "backend"}` and `{action: "stop"}`; `web/src/preview/model.test.ts` groups `app` events by plan, latest wins; `web/src/App.test.tsx` renders no Preview tab when no apps arrive; `npx vitest run`, `npx eslint .` and `npx tsc -b --noEmit` pass.

## F2 Integration check: a real app into the tab

- **Discipline:** front end
- **Covers spec items:** the three "How to tell it's working?" checks
- **Owns:** `web/cypress/preview/preview.cy.ts` (amended: not `cypress/e2e/`, which the demo suite's config runs against port 11000), `web/cypress.preview.config.ts` (its own config: base URL on port 11050, the spec pattern for `preview.cy.ts` only, tasks that touch a fixture file and swap the fixture), `justfile` (a `preview-e2e` recipe), `spec/fixtures/apps/preview_project/` (an `.openlanes.yml` with an `api` and a `web` process reusing `spec/fixtures/apps/servers/`, plus a `deny` variant whose web process sends `X-Frame-Options: DENY`)
- **Must not touch:** `lib/`, `web/src/`, `spec/fixtures/apps/servers/` (B4 owns it), `web/cypress.config.ts` (the demo suite's)
- **Depends on:** B6, F1
- **Done when:** `just preview-e2e` passes against a real `openlanes web --demo` on 11050 (Redis database 13) and a real `openlanes app start --demo`, nothing intercepted, and shows:
  1. `api` reaches ready before `web` starts; the tab shows the web process labelled with plan, branch and port, and the iframe renders the fixture's page.
  1. Touching a file in `api`'s `restart_on` puts the toolbar through restarting to ● running, and the web process's pid (printed by the fixture page) is unchanged.
  1. With the `deny` variant, no iframe renders and the tab offers Open in new window on the app's URL.
