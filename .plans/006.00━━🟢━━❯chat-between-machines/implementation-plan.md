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
| luke-backend (B4) | `lib/openlanes/live/node.rb`, `lib/openlanes/cli/web/web.rb`, `lib/openlanes/web/demo.rb`, `lib/openlanes/web/demo_board.rb`, `justfile`, `spec/openlanes/live/node_spec.rb`, `spec/openlanes/web/demo_spec.rb`, `spec/openlanes/cli/web_spec.rb` |
| rey-frontend (I1) | `web/cypress/peer.ts` (new), `web/cypress.config.ts` |

## Build order

B1, B2, B3 have no dependencies on each other. F1 depends on B1. B4 came out of I1's question, answered 2026-10-14. I1 depends on all.

## What was built

- B1: `contract.md`; `app_spec.rb` "accepts exactly the verbs in the contract's verb table" probes the seven verbs plus three unknown ones.
- B2: `chat_spec.rb` "isolation on one Redis": item 7 (widgets vs gadgets) and item 8 (db 1 vs db 10, via a store reporting its db). The thread example waits with `Thread.pass`; `rg -n sleep spec/openlanes/live/chat_spec.rb` prints nothing. The other timing examples already move the injected clock.
- B3: a real bug. redis-client returns a refused `PSUBSCRIBE` (`NOPERM`) as an error object instead of raising, so `Subscriber#confirm` hit `event.first` and the hub's thread died with a NoMethodError. `Subscriber#read` now raises it as `Unavailable`. `Chat#listen` wraps `#step`: one `UI.log` warning per outage (also on STDERR when no log file or tap would hear it, as under `openlanes web`), `unavailable` in `state`, cleared when a step goes through. The thread uses `listen`. A `Subscriber` whose confirmation fails closes its own connection before raising, since no caller ever holds it to close.

- B4: `openlanes web --demo --identity USER@HOST`. `Live::Node.declared` builds the node through `Node.current` with the declared user and host, so the id is the same `user@host` digest every process registers with, and the checkout id is unchanged: one naming scheme. The demo's board is published as that node (id, user, host, ip, checkout) and leaves the pretend `sam@ci-runner-2` to the demo without an identity, so two demos on one Redis never write the same node. `--identity` without `--demo` is refused (64): a live server's node id keys its claims and commands. `just web-e2e` starts both demos on 11100 and 11101, waits for each `/healthz` (30 s cap), and kills both on exit.
- I1: steps 2 to 4 in `chat.cy.ts`. The second participant is a page on `demo@second-machine`: `cy.request` accepts the invite, says, and leaves; a Cypress task (`web/cypress/peer.ts`) holds that page's `GET /api/events?page=` open, because a server answers `absent` for a machine with no open page, and reads the `said` event the first page's Cmd-Enter message becomes.

## Integration proof

`just web-build && just web-e2e` running `web/cypress/e2e/chat.cy.ts` against two demo servers on one Redis, nothing stubbed: green, see `pull-requests.md`.

## Final run

See `pull-requests.md`.
