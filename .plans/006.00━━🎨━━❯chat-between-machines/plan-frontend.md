# Plan 006.00, front end

`rey-frontend` builds from this file. The page side already exists on this branch: `web/src/chat/` (`useChat.ts`, `bus.ts`, `ChatRoom.tsx`, `MachineMenu.tsx`, `ChatPanel.tsx`, `dialogs.tsx`, `linkify.tsx`, `page.ts`), `web/src/floating/` (`FloatingPanel.tsx`, `useFloatingPanel.ts`), and `web/cypress/e2e/chat.cy.ts`. `just web-test` has never been run against it (spec, Research finding 6). Every unit starts by running its named test against what is there, and writes code only for what fails or is missing.

## F1. Run the web suite and hold the chat to the spec

- **Discipline:** front end.
- **Owns:** `web/src/chat/**` (sources and `Chat.test.tsx`, `page.test.ts`).
- **Must not touch:** `web/src/floating/**` and `web/src/copilot/**` (F2), `web/cypress/**` (I1), `web/src/styles/tokens.css` (the footer ink must stay white, Research finding 5), anything under `lib/` or `spec/`.
- **Depends on:** B1 (the contract it tests against).
- **What:** run `just web-test` first and fix what fails. Then make sure `Chat.test.tsx` has at least one test for each page-side in-scope item, adding what is missing:
  - 1: click opens the board, ▾ and right-click open the menu; status-bar pills unchanged;
  - 2: menu outside a chat, on a machine in the chat, on one not in it, and Invite greyed while an invite waits;
  - 3: Name dialog prefilled from local storage or the machine's user, Enter confirms, cancel after Accept declines;
  - 6: an invite while in a chat says so, and accepting leaves the old chat;
  - 9: line breaks kept, URLs linked, nothing else rendered, 4,000-character cap, Cmd-Enter sends;
  - 10: idle after 60 s untouched (fake timers), back on the next touch, own idleness not shown;
  - 13: header, body and footer colours from the tokens, the tab only while in a chat, a page loaded into a chat starts minimised;
  - 15: the page id survives a reload through session storage and goes as `?page=` on the stream.
- **Done when:** `just web-test` (lint, typecheck, coverage) is green, `web/src/chat/Chat.test.tsx` holds the tests above, and coverage for `web/src/chat/` is above 95%.

## F2. One floating panel for both the copilot and the chat

- **Discipline:** front end.
- **Owns:** `web/src/floating/**`, including `FloatingPanel.test.tsx`; `web/src/copilot/Copilot.tsx` only if its use of the panel must change.
- **Must not touch:** `web/src/chat/**` (F1), `web/cypress/**` (I1), anything under `lib/` or `spec/`.
- **Depends on:** nothing. Runs beside F1 because the two own different files.
- **What:** in-scope items 13 and 14 for the shared part. `FloatingPanel` docks to a side it is given (left for the chat, right for the copilot), collapses to that edge, drags only when open, and returns to its dock corner on minimise and restore. No drag code anywhere else.
- **Done when:** `web/src/floating/FloatingPanel.test.tsx` covers both sides, drag when open, no drag when collapsed, and restore to the dock corner; `rg -ln "pointermove|mousemove" web/src` lists only files under `web/src/floating/`; coverage for `web/src/floating/` is above 95%.

## I1. Integration check: two participants through the real server

- **Discipline:** front end.
- **Owns:** `web/cypress/e2e/chat.cy.ts`.
- **Must not touch:** `lib/openlanes/web/demo_board.rb` and everything else under `lib/` and `spec/`; `web/src/**` (F1, F2). If the demo server cannot host the scenario below, mail `luke-backend` with what it lacks rather than editing it.
- **Depends on:** B1, B2, B3, F1, F2.
- **What:** the one test with nothing stubbed. Cypress drives a page on the demo server (`just web-build`, then `just web-e2e`): real `Web::App`, real `Live::Chat`, real SSE. No `cy.intercept` on `/api/chat` or `/api/events`. The second participant is a second page id acting through `cy.request` on `POST /api/chat/:action` with the page's CSRF token. It must show, in order:
  1. ▾ on another machine's tab opens the menu, Start Chat opens the Name dialog, Enter starts the chat, and the orange panel opens docked bottom left;
  2. the second page accepts the invite and joins; the first page's header lists both names and shows "<name> joined";
  3. a message sent from the panel with Cmd-Enter arrives as a `say` event for the second page; a message the second page sends appears in the first page's panel, with its URL linked;
  4. the second page leaves; the first page shows "<name> left";
  5. a `POST /api/chat/leave` without the token answers 403.
- **Done when:** `just web-e2e` is green with `web/cypress/e2e/chat.cy.ts` covering the five steps, and `rg -n "cy.intercept" web/cypress/e2e/chat.cy.ts` prints nothing.
