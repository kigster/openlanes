# 012.00 App Runner and Preview, front end

`rey-frontend` builds these, against the `apps` / `app` event shape fixed in `plan-backend.md` B1. Do not start F1 before B1 is merged into the branch.

## F1 Preview tab

- **Discipline:** front end
- **Covers spec items:** 10, 11 (opening the window), 13 (no tab without an app)
- **Owns:** `web/src/preview/` (`PreviewTab.tsx`, `PreviewToolbar.tsx`, `useApps.ts`, `preview.css`, and their `*.test.tsx`), `web/src/api/types.ts` (`AppStatus` type, copied from B1), `web/src/api/events.ts` and `web/src/api/events.test.ts` (handle `apps` and `app`), `web/src/api/fixtures/` (an apps fixture), `web/src/App.tsx` (mount the tab only when an app is running)
- **Must not touch:** anything under `lib/` or `spec/`, `web/cypress/`, `web/cypress.config.ts`
- **Depends on:** B1
- **Done when:** `web/src/preview/PreviewTab.test.tsx` shows one tab per running app labelled plan, branch and port, an iframe on `url` when `framing` is `frame`, and an "Open in new window" call to `window.open` with no iframe when `framing` is `window`; `web/src/preview/PreviewToolbar.test.tsx` shows ● running and restarting from `state`, and Restart backend, Open in new window and Stop posting `app.restart` (`target: "backend"`) and `app.stop` through the existing `useSendCommand`; `web/src/App.test.tsx` renders no tab when no `apps` arrive; `npm test` and `npm run lint` in `web/` pass.

## F2 Integration check: a real app into the tab

- **Discipline:** front end
- **Covers spec items:** the three "How to tell it's working?" checks
- **Owns:** `web/cypress/e2e/preview.cy.ts`, `web/cypress.config.ts` (a task that starts and stops `openlanes app start` on the fixture), `spec/fixtures/apps/preview_project/` (a `.openlanes.yml` with an `api` and a `web` process reusing `spec/fixtures/apps/servers/`, plus a `deny` variant whose web process sends `X-Frame-Options: DENY`)
- **Must not touch:** `lib/`, `web/src/`, `spec/fixtures/apps/servers/` (B4 owns it)
- **Depends on:** B6, F1
- **Done when:** `web/cypress/e2e/preview.cy.ts` passes against a real `openlanes web` and a real `openlanes app start`, nothing intercepted, and shows:
  1. `api` reaches ready before `web` starts; the tab shows the web process labelled with plan, branch and port 11101, and the iframe renders the fixture's page.
  2. Touching a file in `api`'s `restart_on` puts the toolbar through restarting to ● running, and the web process's pid (printed by the fixture page) is unchanged.
  3. With the `deny` variant, no iframe renders and the tab offers, and calls, `window.open` on the app's URL.
