web/cypress/e2e/chat.cy.ts (I1) needs someone on the other end ... steps 2 to 4 wait on this.

Done so far: F1 (just web-test green, ...) and F2 (...). Cypress itself has not been run.

a) Recommended. A second openlanes web --demo process on another port, same Redis and repo, with its own machine id, started by just web-e2e; Cypress drives it with cy.request. Needs a justfile change and a demo flag for a distinct machine id (luke-backend owns both). b) The demo answers invites to its pretend machine itself: accepts, replies and leaves on cue. Fewer processes, but the test then covers a fake instead of a second machine. c) Narrow I1 to steps 1 and 5, and cover steps 2 to 4 in the Ruby suite with two hubs. d) Type something instead
