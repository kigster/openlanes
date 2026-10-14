## B1 The demo server cannot host the second participant (I1, steps 2 to 4)
Owner: rey-frontend, technical.

`web/cypress/e2e/chat.cy.ts` needs a real second participant: someone who accepts the invite and sends and leaves. The demo has none. `Live::Chat#target!` refuses an invite to its own machine, and the demo's other machine is pretend (`lib/openlanes/web/demo.rb`), so nothing listens on its chat inbox. A second page id on the same server can never be the invitee.

Options:
1. A second `openlanes web --demo` process on another port, same Redis and repo, with its own node id, started by `just web-e2e`. Cypress then drives its pages with `cy.request` to that port. Needs a `justfile` change and a demo flag for a distinct machine id. Recommended.
2. The demo answers invites to its pretend machine itself (accepts, replies, leaves on cue). Fewer processes, but the test then covers a fake and not a second machine.
3. Narrow I1 to steps 1 and 5 and cover 2 to 4 with the Ruby suite's two hubs.

Recommendation: option 1. `luke-backend` owns `lib/` and `justfile`.

## Done so far
- F1: `just web-test` is green (289 tests, 0 failures). `Chat.test.tsx` covers every listed item; coverage of `web/src/chat/` is 96.96% statements.
- F2: `FloatingPanel.test.tsx` covers both docks, drag, and restore; `web/src/floating/` coverage is 98.01%. All pointer handlers live in `web/src/floating/useFloatingPanel.ts`.
- I1: steps 1 and 5 are in `chat.cy.ts` with no `cy.intercept`. Steps 2 to 4 wait on this question. Cypress itself has not been run.
