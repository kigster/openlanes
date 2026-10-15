# Plan 006.00, back end

`luke-backend` builds from this file. The chat already exists on this branch (spec, Research finding 1): `lib/openlanes/live/chat.rb`, `lib/openlanes/live/subscriber.rb`, `lib/openlanes/web/app.rb` (`GET /api/chat`, `POST /api/chat/:action`), `lib/openlanes/web/events.rb`. Every unit starts by running its named spec against what is there, and writes code only for what fails or is missing. Do not rewrite what passes.

## B1. The chat contract

- **Discipline:** back end.
- **Owns:** `contract.md` in this plan folder (new); one example added to `spec/openlanes/web/app_spec.rb`, inside `describe "the chat between machines"`.
- **Must not touch:** `lib/openlanes/live/chat.rb`, `spec/openlanes/live/chat_spec.rb` (B2), `lib/openlanes/live/subscriber.rb` (B3), anything under `web/`.
- **Depends on:** nothing.
- **What:** write down, from the code as it stands, the three things the pair shares:
  - the `event: chat` payloads relayed by `Web::Events` (each `kind`, its fields);
  - every `POST /api/chat/:action` verb, its JSON body, and its status codes (200, 403 without the CSRF token, 404 unknown verb, 409 settled invite, 422 bad body);
  - the shape of `GET /api/chat?page=` (`chat`, `participants`, `invites`, pending-invite flags the menu needs).
  Note that chat keys use the `openlanes:<repo>:chat:<db>:…` prefix, not the 004 contract's `agentilda:` (spec, Out of scope), and that chat is pub/sub while plan 003's agent mail is Streams (spec, Risks).
- **Done when:** `spec/openlanes/web/app_spec.rb` has an example asserting that the verbs `Web::App` accepts for `/api/chat/:action` are exactly the list in `contract.md`'s verb table, and `bundle exec rspec spec/openlanes/web/app_spec.rb` is green.

## B2. Repository and database isolation, and the timing specs

- **Discipline:** back end.
- **Owns:** `spec/openlanes/live/chat_spec.rb`; `lib/openlanes/live/chat.rb` only if a new example fails.
- **Must not touch:** `spec/openlanes/web/app_spec.rb` (B1), `lib/openlanes/live/subscriber.rb` (B3), anything under `web/`.
- **Depends on:** nothing.
- **What:** add the two checks the spec names that the hub spec lacks today:
  - in-scope item 7: two hubs on one store with two repository names (`github.com/acme/widgets`, `github.com/acme/gadgets`); a start, an invite and a message in one are never seen by the other;
  - in-scope item 8: two hubs on one store with the same repository and db 1 versus db 10 never meet (pub/sub crosses databases, Research finding 2).
  Then confirm every timing example (20 s heartbeat, 60 s roster expiry, 60 s idle, 10 s grace, 60 s invite expiry) drives the injected `clock:` and calls no `sleep`.
- **Done when:** `bundle exec rspec spec/openlanes/live/chat_spec.rb` is green with both new examples, and `rg -n "sleep" spec/openlanes/live/chat_spec.rb` prints nothing.

## B3. The hub degrades when Redis refuses the subscription

- **Discipline:** back end.
- **Owns:** `lib/openlanes/live/subscriber.rb`, `spec/openlanes/live/subscriber_spec.rb` (new).
- **Must not touch:** `lib/openlanes/live/chat.rb` and `spec/openlanes/live/chat_spec.rb` (B2), `spec/openlanes/web/app_spec.rb` (B1). If the hub itself must change, it goes through the existing `Unavailable` rescue in `chat.rb`; ask B2's owner rather than editing it while B2 runs.
- **Depends on:** nothing. Runs beside B2 because the two own different files.
- **What:** spec, Open question 2. A Redis user whose ACL refuses `PSUBSCRIBE openlanes:<repo>:chat:<db>:room:*` (`NOPERM`), or a lost connection, must log one warning and leave the server serving the board, with `GET /api/chat` reporting chat unavailable rather than raising. A `MemorySubscriber` double that raises on subscribe is enough; no real Redis.
- **Done when:** `bundle exec rspec spec/openlanes/live/subscriber_spec.rb` is green, covering a refused subscribe and a dropped connection, and `just lint` reports zero offenses.
