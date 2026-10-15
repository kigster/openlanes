# Plan 006.00: implementation plan

Owner: `luke-backend`. The interfaces are in `contract.md` in this folder; this file holds the rest.

## Baseline

`bundle exec rspec` before any change: 2214 examples, 0 failures. `bundle exec rubocop`: no offenses.

## Interfaces

Every route, payload, verb and error rey's half calls is in `contract.md`. One amendment, in place there: `GET /api/chat` gained `unavailable` (B3).

## File ownership

| Who | Files |
| :-- | :-- |
| luke-backend | `lib/openlanes/live/chat.rb`, `lib/openlanes/live/subscriber.rb`, `spec/openlanes/live/chat_spec.rb`, `spec/openlanes/live/subscriber_spec.rb` (new), `spec/openlanes/web/app_spec.rb`, `contract.md`, this file |
| rey-frontend | `web/src/chat/**`, `web/src/floating/**`, `web/src/copilot/Copilot.tsx`, `web/cypress/e2e/chat.cy.ts` |
| shared | none written. `lib/openlanes/web/demo*.rb` and `justfile` are luke's if I1's B1 is answered with option 1 |

## Build order

B1, B2, B3 have no dependencies on each other. F1 depends on B1. I1 depends on all, and is blocked (`blocked.md` B1).

## What was built

- B1: `contract.md`; `app_spec.rb` "accepts exactly the verbs in the contract's verb table" probes the seven verbs plus three unknown ones.
- B2: `chat_spec.rb` "isolation on one Redis": item 7 (widgets vs gadgets) and item 8 (db 1 vs db 10, via a store reporting its db). The thread example waits with `Thread.pass`; `rg -n sleep spec/openlanes/live/chat_spec.rb` prints nothing. The other timing examples already move the injected clock.
- B3: a real bug. redis-client returns a refused `PSUBSCRIBE` (`NOPERM`) as an error object instead of raising, so `Subscriber#confirm` hit `event.first` and the hub's thread died with a NoMethodError. `Subscriber#read` now raises it as `Unavailable`. `Chat#listen` wraps `#step`: one `UI.log` warning per outage, `unavailable` in `state`, cleared when a step goes through. The thread uses `listen`.

## Integration proof

`just web-build && just web-e2e` running `web/cypress/e2e/chat.cy.ts` against the demo server, nothing stubbed. Not runnable for steps 2 to 4 until `blocked.md` B1 is answered: the demo has no second real machine.

## Final run

See `pull-requests.md`.
