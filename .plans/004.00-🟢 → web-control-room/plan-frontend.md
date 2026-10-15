# Plan 004.00, front end (`rey-frontend`)

The page exists and matches `design/control-room.html`. These units add evidence and fix only what that evidence exposes. Units run in the order F3, F2, F1: F1's focus fixes may land in files F2 tests, so F1 goes last.

## F1 Keyboard-only Cypress flow

- **Discipline:** front end.
- **Owns:** `web/cypress/e2e/keyboard.cy.ts`; focus-order and focus-trap fixes the spec exposes, in components under `web/src/` other than `web/src/api/**`.
- **Must not touch:** `web/cypress/e2e/{actions,board,chat,needs-you}.cy.ts`, `web/src/api/**`, `web/vite.config.ts`, `web/package.json` (F3).
- **Depends on:** F2 (sequential: both may edit `web/src/shell/Header.tsx`).
- **Work:** against `openlanes web --demo`, drive with keys only (Tab, Shift+Tab, Enter, Space, Escape, arrows), no `click` and no pointer events: answer a question from Needs you, hold a blocked agent, stop all local through its confirm dialog, open the Action menu and switch model. After each dialog closes, focus returns to the control that opened it. Run axe after each step.
- **Done when:** `web/cypress/e2e/keyboard.cy.ts` passes, and the existing Cypress specs and Vitest stay green.

## F2 Reconnect banner and read-only peer tab

- **Discipline:** front end.
- **Owns:** `web/src/shell/Header.test.tsx`, `web/src/board/Board.test.tsx`, `web/src/App.test.tsx`; fixes they expose in `web/src/shell/Header.tsx`, `web/src/board/Board.tsx`, `web/src/board/PlanRow.tsx`.
- **Must not touch:** `web/src/api/**` (the SSE client's reconnect is already covered by `events.test.ts`; B3 proves it against real processes), Cypress specs.
- **Depends on:** F3 (sequential: same agent, and F3's script must measure these changes).
- **Done when:** `Header.test.tsx` asserts "reconnecting" shows when the stream errors and clears when it reopens with the board unchanged; `Board.test.tsx` and `App.test.tsx` assert a peer node's tab renders its plans with every control disabled or absent, and that no command is sent from it.

## F3 Vitest coverage of changed files

- **Discipline:** front end.
- **Owns:** `web/scripts/coverage-changed.ts`, `web/scripts/coverage-changed.test.ts`, `web/package.json` (a `coverage:changed` script), `web/vite.config.ts` (the `json` coverage reporter, if not already on).
- **Must not touch:** `.circleci/config.yml` (B5 calls the script), components.
- **Depends on:** nothing.
- **Work:** after `vitest run --coverage`, read `coverage/coverage-final.json`, keep files from `git diff --name-only origin/main...HEAD -- web/src`, print statements per file, exit non-zero below 95%.
- **Done when:** `web/scripts/coverage-changed.test.ts` passes: a file under 95% fails and is named, all at or above passes, no changed files passes.
