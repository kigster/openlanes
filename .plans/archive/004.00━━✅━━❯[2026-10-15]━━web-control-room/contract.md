# Contract: engine, API server, page

The shapes are in `web/src/api/types.ts`, the single source of truth. `web/src/api/fixtures/snapshot.json` is one valid `Snapshot`; the Ruby suite checks `Live::Snapshot#to_h` has the same keys at every level, and the TypeScript suite type-checks the fixture.

## Processes

- **Engine:** `openlanes run`. Runs the dispatcher. Every tick it publishes a `Snapshot` and reads commands.
- **API server:** started by `openlanes run` beside the engine (a separate process, `openlanes web` on its own), Sinatra 4 on Puma, `127.0.0.1:11000`. Holds no state: reads Redis, writes Redis, serves `web/dist`.
- `openlanes run --no-web`: engine only. `--no-open`: do not open the browser. `--port`, `--redis-url`.
- `openlanes web --demo`: the API server over a demo engine that publishes sample snapshots and answers commands, with no agents. Cypress and the front-end dev server run against it.

## Redis keys

`P = openlanes:<repo>`, `<repo>` the normalised GitHub URL (`github.com/owner/name`), `<node>` 24 hex digits of SHA-256(`user@host`), `<checkout>` 12 hex digits of SHA-256(realpath of the checkout).

| Key | Type | Written by | Holds |
| --- | --- | --- | --- |
| `P:nodes` | hash | each engine | `<node>:<checkout>` → JSON `Node`, refreshed every heartbeat |
| `P:<node>:<checkout>:snapshot` | string | engine | latest `Snapshot` JSON, `EX 30` |
| `P:<node>:<checkout>:board` | stream | engine | `{seq, json}` per published snapshot, `MAXLEN ~ 100` |
| `P:<node>:<checkout>:commands` | stream | API server | `{json}` one `Command`; engine reads with group `engine` |
| `P:<node>:<checkout>:replies` | stream | engine | `{json}` one `Reply`, `MAXLEN ~ 1000` |
| `P:<node>:<checkout>:done` | hash | engine | command id → `Reply` JSON, for redelivery (W13); trimmed after a day, unreadable entries dropped |
| `P:<node>:<checkout>:copilot` | stream | API server | `{json}` one `CopilotTurn`, the person's and the copilot's in the order said, `MAXLEN ~ 500` (W17) |
| `P:<node>:<checkout>:copilot-session` | hash | API server | `session` (copilot's `claude` session id), `model`, `up`, `down`: the conversation to resume and what it has spent (W17) |
| `P:<node>:<checkout>:run` | hash | engine | `seq` and `json`: the run state a person set (held questions, held cars, queued models), written in the same `MULTI` as the reply that changed it; mirrored into `.plans/openlanes-state.json` under `live`, and on start the copy with the higher `seq` wins (W6) |
| `P:claim:<ordinal>` | string | engine | `<node>:<checkout>`, `SET NX EX 90`, renewed by heartbeat, released by compare-and-delete |

A node is alive while its `snapshot` key exists. Whoever reads `P:nodes` drops the fields whose snapshot has expired, and an engine that closes cleanly removes its own. A checkout with no `origin` is `local/<dirname>-<12 hex of SHA-256 of its real path>`. The API server reads every node's snapshot for the repository; it writes commands only to its own node's stream.

## HTTP

| Method, path | Does |
| --- | --- |
| `GET /` and static | `web/dist`; `index.html` for unknown non-API paths |
| `GET /api/board` | `Board` JSON now |
| `GET /api/events` | SSE: first `event: cursor` with `id:` and `{id}` set to the newest reply id (`0-0` when there is none), so a reconnect always has a `Last-Event-ID`; then `event: board` with a `Board` whenever any snapshot's `seq` changes (checked every 250 ms), `event: reply` with each `Reply`; then `event: copilot_cursor` with `{id}`, the newest copilot turn's stream id (`0-0` when there is none), and `event: copilot` with each `CopilotTurn` written after it, neither with an `id:` so they never move the reply cursor; with `?page=<id>`, `event: chat_cursor` once that page is attached to its chat (the page reads `GET /api/chat` on it), then `event: chat` with each `ChatEvent` for the page, no `id:`; a `: ping` comment every 15 s |
| `POST /api/commands` | body `Command`; header `X-CSRF-Token` must equal the token in `GET /api/session`; `202` with `Reply{status: "accepted"}` once queued, `422` with `Reply{status: "refused"}` for an invalid command |
| `GET /api/copilot` | `CopilotLog`: the newest 100 turns, oldest first, and the copilot's latest `usage` (`{model: null, up: 0, down: 0}` before it has any) |
| `POST /api/copilot` | body `CopilotMessage` `{id, text}`, text at most 4000 characters; same `X-CSRF-Token` rule; `202` with the person's `CopilotTurn` once stored, `422` with `{error}` for a message it refuses, `503` with `{error}` when nothing in this server answers the copilot (the message is not stored). The answers arrive as `event: copilot` |
| `GET /api/chat?page=<id>` | `ChatState` (plan 006): `{chat: {id, me, participants} or null, invites, outgoing}` for that page; `422` for a page id that is not 8–64 letters, digits, `-` or `_` |
| `POST /api/chat/:action` | `start {page, name, machine}`, `invite {page, machine}`, `accept {page, invite, name}`, `decline {page, invite}`, `leave {page}`, `say {page, id, text}` (at most 4000 characters), `presence {page, idle}`; same `X-CSRF-Token` rule; `202` with the action's answer, `422` with `{error}` when refused, `409` for an invite already answered or expired. Everyone hears of it as `event: chat` |
| `GET /api/session` | `{csrf, node, repo}` |
| `GET /api/plans/:ordinal/files/:name` | the Markdown of a plan file (spec.md, plan.md, blocked.md), for the drawer and preview |
| `GET /healthz` | `ok` and the Redis address, password masked |

The page reconnects with `@microsoft/fetch-event-source`, and on reconnect fetches `/api/board` once. It reads `/api/copilot` each time a `copilot_cursor` arrives, so the read covers every turn up to that boundary and the stream every turn after it.

## Copilot (W17)

The conversation with copilot travels like everything else: messages go in by POST, answers come out on the one event stream. A `CopilotTurn` is `{id, from: "you" | "copilot", kind, text, at, usage}`; a reply's id is the message's id, a dot and its place (`01J….1`), so it names what it answers. `kind` is one of:

| kind | extra fields | the page draws |
| --- | --- | --- |
| `text` | none | the words |
| `confirm` | `command` (a `Command` without its id), `confirm` (the button's label), `done` (what the card says once accepted) | a red card; the command is sent through `POST /api/commands` only when the person presses the button (stop, discard, stop all) |
| `draft` | `question` (a `Question.id`), `draft` | a quiet card that puts the draft in that question's answer box without sending it |

The server refuses to store a card missing its fields, or a confirm card whose command `POST /api/commands` would refuse.

### Where copilot runs

In the API server, not the engine. The conversation already arrives there and is stored there, and W17 asks for nothing the engine alone has: the agent reads the board, the plan folders, the mailboxes and the transcripts, all of which the server can reach. Running there also means it answers under `openlanes web` with no run going, and after a run has ended. `openlanes web --demo` answers with one canned line instead (`Web::Demo::COPILOT`); a server with no responder answers `POST /api/copilot` with `503`.

- **One message at a time.** `POST /api/copilot` stores the person's turn and returns `202` at once; the server then calls `Copilot#answer` on its background path (`Context#background`, a thread with its own Redis connection), whose responder is `Live::Copilot::Operator`. The operator answers one message after another, so two `claude` processes never resume one session; a failure is written as a `text` turn by `Copilot#answer`.
- **One session, resumed.** Each message is one `claude -p`, with `--resume <session>` from `copilot-session` when there is one, so a reloaded page or a restarted server carries on the same conversation. A session `claude` no longer has fails before spending anything; the operator then starts a fresh one and keeps its id. A message still queued when the server stops is not answered.
- **What it is told.** Its definition (`agents/copilot.md`) goes as `--append-system-prompt` on every call, so compaction cannot lose it. Each message carries the board as the server read it from Redis (this node's plans, cars, questions and recent log, other machines in one line each), where to read further, and the person's words.
- **Its boundary.** `--restricted --tools Read,Grep,Glob,Bash --permission-mode dontAsk`: no other built-in tool exists for it, no settings file can widen what is allowed, and anything not allowed is refused rather than prompted for. Bash runs only the read-only `openlanes` queries its definition lists. `Executor#denied_for` adds the network tools and every command that leaves the machine, and `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Task` and `Agent` are denied on top. It reads the checkout and the trace directory (`--add-dir`), on its definition's model (`haiku`), with a 180 s limit per answer.
- **Usage.** Every turn it writes carries `usage`: the model's full id and the session's running `up` and `down`, which the header shows.
- **Failures** come back as a `text` turn saying why ("copilot could not answer: …"), never as silence.

### Cards copilot writes

The agent answers in prose. Where it wants a card it writes a fenced block whose info string is exactly `copilot`, holding one JSON object:

````text
```copilot
{"card": "confirm", "text": "…", "command": {"kind": "stop", "plan": "002", "agent": "backend-coder"}, "confirm": "Stop backend-coder", "done": "…"}
```
```copilot
{"card": "draft", "question": "002/B1", "text": "…", "draft": "…"}
```
````

`Live::Copilot::Cards` cuts the answer into turns in the order written (`<id>.1`, `<id>.2`, …) and draws a card only when all of these hold; otherwise the block becomes a `text` turn giving the reason and the block's body, and nothing is offered:

- it parses as one JSON object, and `card` is `confirm` or `draft`;
- a confirm card's `command.kind` is `stop`, `discard` or `stop_all`, `Command.parse` accepts it, and the plan (and for `stop` the agent) is on this node's board; its payload is dropped, so the card carries only what its button says; `confirm` is 1 to 60 characters and `done` 1 to 200;
- a draft card's `question` is an id on this node's board, and `draft` is not empty;
- the answer has offered no more than three cards.

`message`, `hold` and every other kind are refused as cards: the engine files a `message` in the mailbox as from `human`, and the copilot's words must not reach an agent under the person's name. A fence with another info string, or one never closed, stays prose. The server never sends a card's command itself: the page does, through `POST /api/commands`, when the person presses the button.

## Chat between machines (plan 006)

Pages on machines sharing one Redis chat through Redis pub/sub; nothing said is stored. Each API server subscribes once, relays to its pages over the event stream, and takes their actions by POST.

| Channel or key | Type | Carries |
| --- | --- | --- |
| `P:chat:<db>:room:<chat>` | pub/sub, every server through `PSUBSCRIBE P:chat:<db>:room:*` | `join`, `here`, `say`, `idle`, `back`, `leave`, each `{kind, from: ChatParticipant, …}` |
| `P:chat:<db>:machine:<node>` | pub/sub, every server for that node id | `invite {invite: ChatInvite}`, `absent {invite}`, `settled {invite, answer}` |
| `P:chat:invite:<invite>` | string, `SET NX EX 120` | `accepted`, `declined` or `expired`: the first answer wins |

`<db>` is the Redis database number, because `PUBLISH` reaches every database. `<node>` is the 24-hex node id, so an invite reaches every page open on that machine. A `ChatEvent` is one of `joined`, `left`, `idle`, `back`, `roster`, `said`, `invited`, `invite_closed`, `declined`, `unanswered` (types in `web/src/api/types.ts`). A page whose stream closes counts as gone after 10 s; invites expire after 60 s; a participant not heard from (a `here` every 20 s) for 60 s counts as gone.

## Commands, as the engine applies them

| kind | effect |
| --- | --- |
| `answer` | append `## A<n>` with the text, "Answered by <user> on <date>" and `<!-- cmd:<id> -->`, to blocked.md; once every `B<n>` has an answer the dispatcher hands the plan to the agent that handles its state (unblocker) through `Lifecycle::Unblocker`, on a thread, and picks the plan up again in the same run. Each answer set is tried once; a failed drain waits for blocked.md to change |
| `hold_blocked` / `release_hold` | mark the question held in the run state; the page shows the pill solid red ⏸ |
| `resume` | resume the interrupted agent from its last-known-state with the note in its mailbox |
| `discard` | plan-wide (W9): stop every agent on the plan (STOP, then SIGKILL after 15 s), `git reset --hard` and `git clean -fd` in the plan's own worktree (its branch's last commit; agents never commit), then move the folder back one state through `StateMachine#retreat!`. The reply waits until all of it is done. Refused up front under `--isolation shared` or a dry run, and for a state with nothing behind it on the spine (🔴 🚫 ⏪) or whose earlier state the folder does not fit |
| `message` | append to the plan's mailbox, from `human`, to the agent; the entry carries the command id, so a redelivered command appends nothing |
| `hold`, `wrap_up`, `stop` | write the word to that agent's control file (`HOLD`, `WRAP_UP`, `STOP`) |
| `compact` | W28. `/compact` is the caller's command, not one an agent can run on itself, so the harness does it from outside, under the agent's own handle, so the board shows one car carrying on: (1) INTERRUPT into the control file, so the agent leaves a resume note and ends its turn, SIGKILL after 60 s if it has not; (2) `claude -p --resume <session_id> "/compact"` with the same flags, less `--disable-slash-commands` (with it, claude answers "/compact isn't available in this environment"); success is the stream's `compact_boundary` event; (3) `claude -p --resume <session_id> "<continuation prompt>"` on the same model. The reply is `done` once the continuation has started, `refused` with the reason when a step fails; then the agent's round is handed back and it restarts from its resume note in a fresh session. The session id is the one in claude's `init` event, kept on the handle and the board row. An agent that has not named its session yet is restarted from its resume note in a fresh session instead, and the reply says so. Refused for an agent on `codex` or `pi`, which cannot resume a session |
| `stop_all` | `Execution::Control.quit!` on this node |
| `set_model` | the model for that agent's next round on this plan, normalised to the id the CLI will run (a model above the adapter's ceiling is refused) |
| `switch_model` | `set_model`, then the three steps of `compact`, with the `/compact` and the continuation run with `--model <new model>`, so the agent carries on in its own session on the new model. Where the session cannot be resumed (no session id yet, or a `codex`/`pi` agent) it falls back to INTERRUPT and a restart on the new model in the same round, from the resume note in a fresh session, and the reply says why |
| `add_plan` | claim the plan, add it to the run's scope |
| `create_plans` | `Lifecycle.create` a plan from the idea, its spec.md carrying `<!-- cmd:<id> -->`, then `add_plan`; a plan already carrying the marker is added rather than created again |

Every reply goes on `replies` and into `done`. A command whose id is already in `done` is acked and answered with its first reply. Effects outside Redis are idempotent by command id (the markers above, the mailbox's `command`), so a command applied again after a failed `MULTI` changes nothing twice.
