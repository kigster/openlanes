# Blocked: 006.00 chat-between-machines

Asked by rey-frontend, 2026-10-13. Technical.

## B1 How does the Cypress chat test get a real second participant?

`web/cypress/e2e/chat.cy.ts` (I1) needs someone on the other end who accepts the invite, sends a message and leaves. The demo server has nobody there: `Live::Chat#target!` refuses an invite to its own machine, and the demo's other machine is pretend (`lib/openlanes/web/demo.rb`), so nothing listens on its chat inbox. Steps 1 and 5 of I1 are written; steps 2 to 4 wait on this.

Done so far: F1 (`just web-test` green, 289 tests, `web/src/chat/` 96.96% covered) and F2 (`web/src/floating/` 98.01% covered). Cypress itself has not been run.

a) **Recommended.** A second `openlanes web --demo` process on another port, same Redis and repo, with its own machine id, started by `just web-e2e`; Cypress drives it with `cy.request`. Needs a `justfile` change and a demo flag for a distinct machine id (luke-backend owns both).
b) The demo answers invites to its pretend machine itself: accepts, replies and leaves on cue. Fewer processes, but the test then covers a fake instead of a second machine.
c) Narrow I1 to steps 1 and 5, and cover steps 2 to 4 in the Ruby suite with two hubs.
d) Type something instead
