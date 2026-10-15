# Plan 006.00: the chat contract

Owner: `luke-backend`. Written from the code as it stands (`lib/openlanes/live/chat.rb`, `lib/openlanes/web/app.rb`, `lib/openlanes/web/events.rb`). `spec/openlanes/web/app_spec.rb`, "accepts exactly the verbs in the contract's verb table", holds the verb table below to the route.

## Keys and transport

- Chat keys use `openlanes:<repo>:chat:<db>:…`, not the 004 contract's `agentilda:` prefix. Updating 004 is out of scope; this is the note.
  - room: `openlanes:<repo>:chat:<db>:room:<chat uuid>` (every server holds one `PSUBSCRIBE …:room:*`);
  - inbox: `openlanes:<repo>:chat:<db>:machine:<node id>` (`SUBSCRIBE`);
  - first answer to an invite: `openlanes:<repo>:chat:invite:<uuid>`, `SET NX EX 120` (a key, so per database already).
- The chat is Redis pub/sub and stores nothing (D2). Plan 003's agent mail is Redis Streams. They share nothing but the server.
- Pages receive over `GET /api/events?page=<page id>` and act by `POST /api/chat/:action`.

## `GET /api/chat?page=<page id>`

`200`:

| Field | Shape |
| :-- | :-- |
| `chat` | `null`, or `{id, me: Participant, participants: [Participant]}` |
| `invites` | `[Invite]` open to this machine |
| `outgoing` | `[{id, machine, label}]`, invites this page waits on; non-empty greys Invite to Chat |
| `unavailable` | `null`, or the reason Redis refused the subscription (amended: B3, the page may say the chat is unavailable) |

`422 {error}` for a page id that is not 8 to 64 of `[A-Za-z0-9_-]`. `404 {error}` when the server has no chat.

- `Participant`: `{id, name, machine, label, idle}` (`label` is `user@host`).
- `Invite`: `{id, chat, from: Participant, machine, label, expires_at}` (ISO 8601 UTC).

## `POST /api/chat/:action`

Header `X-CSRF-Token` (from `/api/session`), JSON object body, always with `page`. Success is `202`.

| Verb | Body | `202` body |
| :-- | :-- | :-- |
| `start` | `page, name, machine` | `{chat, invite}` |
| `invite` | `page, machine` | `{id, machine, label}` |
| `accept` | `page, invite, name` | `{chat}` |
| `decline` | `page, invite` | `{}` |
| `leave` | `page` | `{}` (also for a page in no chat) |
| `say` | `page, id, text` | `{id, text, at, who: Participant}` |
| `presence` | `page, idle` (boolean) | `{}` |

Errors, each `{error: <sentence>}`:

- `403` without a matching `X-CSRF-Token`, checked first;
- `404` for a verb not in the table ("no such chat action: …"), or a server with no chat;
- `409` accept or decline of an invite already answered, expired or never seen;
- `422` body not a JSON object; bad page id; name empty or over 60; machine not a node id, this machine, or not on the board; text empty or over 4,000; message id not 1 to 64 of `[A-Za-z0-9_-]`; invite or say while in no chat.

## `event: chat` on `GET /api/events`

No `id:`. A stream with `?page=` opens with `event: chat_cursor` `{}`; read `GET /api/chat` after it. Each `event: chat` is one of:

| `kind` | Fields |
| :-- | :-- |
| `invited` | `invite: Invite` (every page on the machine) |
| `invite_closed` | `invite` (id), `answer`: `accepted`, `declined` or `expired` |
| `declined` | `invite, machine, label` (the inviting page) |
| `unanswered` | `invite, machine, label` (the inviting page; at once when nobody listens) |
| `joined` | `chat, who: Participant, participants` |
| `left` | `chat, who: Participant, participants` (Stop Chat, 10 s grace, or 60 s without `here`) |
| `idle`, `back` | `chat, who: Participant, participants` |
| `roster` | `chat, participants` |
| `said` | `chat, who: Participant, id, text, at` |

## Timing (server side)

Heartbeat 20 s, forgotten after 60 s, stream grace 10 s, invite 60 s. Idle (60 s untouched) is measured by the page, which posts `presence`.
