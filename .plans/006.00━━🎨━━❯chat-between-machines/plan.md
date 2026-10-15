# Plan 006.00: Chat Between Machines

## Starting point

The spec's Risks put it first: the chat is already built on this branch (Research, finding 1). Hub, routes, relay, page components, the shared floating panel and a Cypress spec all exist, and the Ruby suite is green. So these units close gaps and prove the in-scope list. They do not build from scratch. Each unit runs its named test against the code as it stands, and changes code only where that test fails or is missing.

Gaps found against the spec's in-scope checks:

- no written contract between the two halves (spec, "Back end / front end");
- no hub spec for two repositories on one store (item 7), or for db 1 against db 10 (item 8);
- no degrade path specified for a refused `PSUBSCRIBE` (Open question 2);
- `just web-test` never run, and coverage of `web/src/chat/` unmeasured (Research, finding 6);
- the Cypress chat spec has not been checked as an unstubbed end-to-end run.

## Units

| Id | Unit | Discipline | Owns | Depends on | Done when |
| :-- | :-- | :-- | :-- | :-- | :-- |
| B1 | The chat contract | back end | `contract.md`, one example in `spec/openlanes/web/app_spec.rb` | nothing | `spec/openlanes/web/app_spec.rb` |
| B2 | Repo and db isolation, timing specs | back end | `spec/openlanes/live/chat_spec.rb`, `lib/openlanes/live/chat.rb` | nothing | `spec/openlanes/live/chat_spec.rb` |
| B3 | Degrade on a refused subscription | back end | `lib/openlanes/live/subscriber.rb`, `spec/openlanes/live/subscriber_spec.rb` | nothing | `spec/openlanes/live/subscriber_spec.rb` |
| F1 | Web suite green, chat held to the spec | front end | `web/src/chat/**` | B1 | `web/src/chat/Chat.test.tsx`, `just web-test` |
| F2 | One floating panel for both | front end | `web/src/floating/**`, `web/src/copilot/Copilot.tsx` | nothing | `web/src/floating/FloatingPanel.test.tsx` |
| I1 | **Integration check**, two participants through the real server | front end | `web/cypress/e2e/chat.cy.ts` | B1, B2, B3, F1, F2 | `web/cypress/e2e/chat.cy.ts`, `just web-e2e` |

The full shape of each unit (owns, must not touch, depends on, done when) is in `plan-backend.md` (B1–B3) and `plan-frontend.md` (F1, F2, I1).

## Order

1. **First, together:** B1, B2, B3 and F2. None of them shares a file with another.
1. **After B1:** F1. It tests the page against the contract B1 writes.
1. **Last:** I1, after every other unit.

Sequential because of shared files or shared ground:

- B2 and B3 both border `lib/openlanes/live/chat.rb`. B2 owns it. If B3 needs a change there, it waits for B2.
- F1 and F2 meet where `ChatPanel.tsx` uses `FloatingPanel`. F1 owns the caller and F2 the panel. A change to the panel's props goes in F2 first.
- I1 reads everything and writes only its Cypress file, so it runs last.

## Dependency graph

```mermaid
flowchart LR
  B1[B1 contract] --> F1[F1 chat page tests]
  B1 --> I1
  B2[B2 isolation specs] --> I1
  B3[B3 subscribe degrade] --> I1
  F1 --> I1
  F2[F2 floating panel] --> I1
  I1[I1 integration: Cypress, nothing stubbed]
```

## Integration check

The Cypress integration check is removed: `web/cypress/e2e/chat.cy.ts` is not built, and no browser test drives a second participant through the real server.

Decided 2026-10-15 by kig: remove this Cypress test.

The steps below are the original I1 check, kept for reference until the units are re-planned. I1 owns it. Cypress drives a real page on the demo server: real `Web::App`, real `Live::Chat`, real SSE, and no `cy.intercept` on chat or events. A second page id joins through `POST /api/chat/:action`. The run must show these steps:

- start from the ▾ menu;
- the Name dialog;
- the panel docked bottom left;
- the second page joining, and both names in the header;
- a message each way, with a URL linked;
- "<name> left";
- 403 on a POST without the CSRF token.

## Size

Six units, one pull request. Each unit adds or extends one spec file and a reviewer can check it in one sitting.

## Not in this plan

These are the spec's Out of scope list, and none is built here:

- updating the 004 contract's `agentilda:` prefix (B1 only notes it);
- load-testing Puma's SSE threads;
- Redis ACL provisioning;
- message history;
- avatars;
- any change to the copilot's behaviour or colours.
