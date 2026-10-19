# Chat Between Machines

## What we are trying to achieve

Machines on the same repository and the same `$REDIS_URL` can chat with each other from the control room.

Decided 2026-10-13 by kig: chat is scoped to one repository, so machines on different repositories sharing a `$REDIS_URL` never meet in chat.

- Each other machine's tab gets a ▾ (or a right-click) that opens a menu with **Start Chat**, which becomes **Stop Chat** once a chat is running.
- **Start Chat** opens a centred dialog asking for a **Name**, how the person wants to appear in the chat. (An avatar URL comes later, not in this plan.)
- The first person to start a chat mints a UUID for it and starts streaming over Redis pub/sub. After that, each other machine's dropdown says **Invite to Chat**.
- An invited person gets a centred modal naming who invited them. **Decline** closes it, and no chat with that person happens. **Accept** shows the same Name dialog, and **Join** puts them in the chat.
- A chat is its own object, with two or more participants. Messages go from the publisher to every other participant through Redis pub/sub.
- The chat panel looks like the copilot from plan 004's design (`design/control-room.html`, W17), in its own colours:
  - header `#D9420B` with black text, listing the names of the people in the chat;
  - body white, text `#222`;
  - footer a darker orange around the text area and the **Send** button; Cmd-Enter sends.
- The panel starts collapsed and glued to the left edge of the window. Opened, it can be dragged around the screen. Minimised and restored, it goes back to the bottom left.
- The chat shows the messages people send, and when someone joins, leaves, or goes idle after 60 seconds without touching the chat.

## Why it matters

Machines on one Redis already work side by side on the same plans (W26, W29), but the people behind them have no way to talk from the page they share.

## What already exists

- Other machines on the same Redis (W26) already appear twice: as a tab each beside Board and Logs (`web/src/App.tsx`, `machineTab`), and as pills on the status bar (`web/src/shell/StatusBar.tsx`). Clicking either opens that machine's read-only board.
- The copilot panel was designed in plan 004 (`design/design.md`, "Header and copilot"; decision W17) but never built: the spec deferred it, and only its colour tokens (`--copilot-head`, `--copilot-body`) are in `web/src/styles/tokens.css`. This plan builds the floating panel.
- The live run already talks to Redis through `Live::Session`, and the page gets server state over SSE.

## What research needs to settle

Open questions are settled one at a time in `decisions.md` before planning.

## Research

The section above names no list, so the questions are the ones `decisions.md` leaves to the planner ("Left to the planner" and "Implementation choices"), plus the claims they rest on.

1. Does the chat already exist in this branch, and is it wired end to end?
2. Does Redis pub/sub deliver across database numbers, and does the database-in-name scheme isolate machines?
3. Are the Redis primitives used (`SET NX EX`, `PSUBSCRIBE`, separate subscribe connection) correct?
4. What do plans 003, 004 and the decisions say that conflicts with this one?
5. Do the colours meet contrast for the text they carry?
6. Which test commands run, and do they pass?

### Findings, Conclusion & References

**1. The chat is built in this branch.**
- `lib/openlanes/live/chat.rb` is the hub: start, invite, accept, decline, leave, say, presence and heartbeat (`chat.rb:29`, `:201-251`, `:592`).
- Routes: `GET /api/chat` (`lib/openlanes/web/app.rb:203`) and `POST /api/chat/:action` (`app.rb:212-234`). The SSE relay is `lib/openlanes/web/events.rb:23-27`, `:66-91`.
- Client: `web/src/chat/ChatRoom.tsx`, `MachineMenu.tsx`, `ChatPanel.tsx` (on the shared `web/src/floating/FloatingPanel.tsx`), `dialogs.tsx`, `useChat.ts`.
- Specs: `spec/openlanes/live/chat_spec.rb`, `web/src/chat/Chat.test.tsx`.
- Plans 004 and 006 both say the copilot was never built. The code disagrees: `web/src/copilot/Copilot.tsx:151` already uses `FloatingPanel`. Read as "the copilot exists and is wired to a placeholder", which is what plan 004 says (`004/.../spec.md:29`).
- `#D9420B` appears at `web/src/styles/tokens.css:23` as `--chat-head`, and `--chat-foot: #B23507` at the same line.

**2. Database numbers and pub/sub.**
- Redis pub/sub ignores database numbers: "Publishing on db 10, will be heard by a subscriber on db 1." (https://redis.io/docs/latest/develop/pubsub/, retrieved 2026-10-13). The `chat:<db>` segment in each channel name is therefore the only thing separating nodes on different databases. That matches `decisions.md` ("Implementation choices", transport).
- Cluster has only database 0 and SELECT is refused (https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/). The `<db>` segment is then always `0`, which is harmless.
- Caveat: in a cluster, `PUBLISH` replies count only subscribers on the publishing node (https://redis.io/docs/latest/commands/publish/). The chat does not use that count (not checked beyond `chat.rb` reads).
- Delivery is at-most-once; a message is lost if no subscriber is listening (https://redis.io/docs/latest/develop/pubsub/). This is D2's accepted trade-off. The 60-second roster heartbeat (`decisions.md`, "Roster without storage") is what recovers presence after a blip.

**3. Redis primitives.**
- `SET key value NX EX n` returns `OK` on success and null when the key exists (https://redis.io/docs/latest/commands/set/). `Store#set` returns `== "OK"` (`lib/openlanes/live/store.rb:94`, `:277`), so a null reply is `false`. Used for invite answers at `chat.rb:414` and `:428` with `INVITE_TTL * 2`.
- Atomicity of `SET NX` is implied by the documented lock pattern, not stated as a guarantee (not verified further).
- A subscribing connection cannot run ordinary commands, and blocks its thread (https://redis.io/docs/latest/commands/subscribe/, https://redis.io/docs/latest/develop/use-cases/pub-sub/ruby/). The code keeps a separate subscribe client (`lib/openlanes/live/subscriber.rb:25`, `store.rb:228`), so this is satisfied. The gem version was read from `Gemfile.lock:130` (`redis-client` 0.31.0), not from the docs.
- ACL: `PSUBSCRIBE` needs its pattern to match a user's allowed channel pattern literally (https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/). The hub subscribes with `…:room:*` (`subscriber.rb:27`). A production user limited to narrower channels would be refused. Whether production has such a user is not verified.
- Puma runs 2 to 64 threads (`lib/openlanes/web/server.rb:17-18`). Each open page holds one thread for its SSE stream, so about 64 open pages on one server would starve it. Not measured.

**4. Contradictions.**
- **Repository scope.** The spec says "machines share one `$REDIS_URL`". The code, the 004 contract (`004/.../contract.md:14`, `:100`) and the 004 help copy (`004/.../design.md:131`) all scope chat to one repository. Raised as B1.
- **Key prefix.** The 004 contract uses `agentilda:<repo>:…`; the code and `decisions.md` use `openlanes:<repo>:chat:…`. Production runs the `openlanes` prefix (the code). The contract is stale for chat. Technical; recommend updating the contract.
- **Streams versus pub/sub.** Plan 003 chooses Redis Streams for agent mail and calls pub/sub lossy (`003/.../spec.md:34`, `:60`). Plan 006 D2 chooses pub/sub for chat. The use cases differ, so the code does not clash; but the two plans set opposite conventions on the same server and 006 does not mention 003. Technical; recommend a line in 006 noting the difference.
- **Docking side.** The spec and D11 dock the chat left. 004's design only has a right-edge tab (`004/.../design.md:71`). D1 says the chat "follows design.md". Not a clash in the code; the design doc is silent on the left variant.
- **Copilot status.** Plan 004 says a placeholder ships; plans 004 and 006 both say "never built" in places; the code has the component. Production runs whatever `main` has, which I did not check.
- **W26 and W29.** Cited by 004 and 006 as settled, but their text lives in `docs/decisions/`, which I did not open. Not verified.

**5. Colours.**
- Header: black `#000` on `#D9420B` is 4.73:1 (passes AA). White would be 4.44:1 (fails), so black is right.
- Body: `#222` on white is 15.91:1.
- Footer: white on `#B23507` is 6.17:1 (passes). Black would be 3.41:1 (fails). This confirms the footer ink in `decisions.md` ("Implementation choices"), and the tokens already use white.

**6. Tests.**
- `bundle exec rspec` (run through `just test`): 2214 examples, 0 failures, exit 0 (`/tmp/leah-rspec.log`).
- Web: `just web-test` (`lint`, `typecheck`, `coverage`) was not run. Not verified.

**Open questions (for yoda)**

1. Should chat be scoped to one repository, or to any repository on the same `$REDIS_URL`? (B1, product.)
2. Does production run a Redis user whose ACL can `PSUBSCRIBE` the `openlanes:<repo>:chat:*` pattern?
3. How many open control-room pages can one server hold before Puma's thread pool starves?
4. Should the 004 contract be updated from `agentilda:` to `openlanes:` for chat keys?
5. Should 006 cite plan 003's Streams decision and say why chat differs?
6. Does `main` already contain the copilot component, or only the placeholder?

**Conclusion**

- The Redis design holds: pub/sub reaches every database, so the `<db>` segment isolates nodes as intended.
- The chat exists in this branch and passes the Ruby suite. The web suite is unrun.
- One blocking product question (B1, repo scope) is in `blocked.md`. The rest are technical and listed above.

**References**

- Redis pub/sub: https://redis.io/docs/latest/develop/pubsub/ (retrieved 2026-10-13)
- Redis PUBLISH: https://redis.io/docs/latest/commands/publish/ (retrieved 2026-10-13)
- Redis SUBSCRIBE: https://redis.io/docs/latest/commands/subscribe/ (retrieved 2026-10-13)
- Redis SET: https://redis.io/docs/latest/commands/set/ (retrieved 2026-10-13)
- Redis Cluster spec: https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/ (retrieved 2026-10-13)
- Redis ACL: https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/ (retrieved 2026-10-13)
- redis-rb pub/sub: https://redis.io/docs/latest/develop/use-cases/pub-sub/ruby/ (retrieved 2026-10-13)
- Repository files: `lib/openlanes/live/*.rb`, `lib/openlanes/web/*.rb`, `web/src/chat/*`, `web/src/styles/tokens.css`, `Gemfile.lock` (read 2026-10-13)


## Framing

Two ways to frame the problem:

1. **A new transport feature.** Chat is Redis pub/sub between machines; the UI is a thin skin. The risk sits in delivery, presence and Redis topology.
1. **A second floating panel with a roster.** Chat is a page-level UX (menu, dialogs, panel, presence) that happens to be fed by a hub on the API server. The risk sits in the page states: invited, naming, in chat, idle.

Picked **1 plus 2 as one unit, split by half**: the hub and routes are the back end, the panel and dialogs are the front end. One line why: `decisions.md` (D2, "Implementation choices") already fixes the transport, so what is left to get wrong is the contract between the two halves, and the split by half is the one `luke-backend` and `rey-frontend` can build as a pair.

The problem statement above stands. Research changed one thing: it was written as if the chat were unbuilt, while the branch already holds an implementation (Research, finding 1). This plan therefore specifies the behaviour the existing code must be held to, and the planner's units are completion and verification work, not a greenfield build.

## Goal

A person looking at one machine's control room can start a chat with another machine on the same repository and the same `$REDIS_URL`, invite more machines, and exchange plain-text messages in a floating panel, with joins, leaves and 60-second idleness shown. Nothing about this is possible today: machines share plans through Redis but their people have no channel between pages.

## Non-Goals

- **Message history.** Pub/sub is at-most-once and nothing is stored (D2). A late joiner sees nothing from before.
- **Avatars or profile images.** The Name dialog asks for a name only; an avatar URL is a later plan.
- **Chat across repositories.** Machines on different repositories sharing a `$REDIS_URL` never meet (decided 2026-10-13 by kig, top of this spec).
- **Merging with the AI copilot.** The copilot (c3po-operator, W17) stays a separate panel with its own colours (D11).
- **Rich text.** No Markdown, attachments, reactions or typing indicators (D10).
- **A host role or moderation.** Anyone in a chat may invite; nobody can remove anyone (D5).
- **Multiple chats per page.** One chat per page at a time (D4).
- **Delivery guarantees or push notifications when no page is open.** An invite with no open page on the target is reported as unanswered (D9).

## In scope

Each item has its check.

1. **Machine menu.** A ▾ on each other machine's tab, and right-click on it, opens a menu; clicking the tab still opens its board (D3). Check: `web/src/chat/Chat.test.tsx` covers click versus caret versus right-click; status-bar pills unchanged.
1. **Menu states.** Outside a chat: Start Chat. In a chat: Stop Chat on a machine already in it; Invite to Chat (greyed while an invite waits) and Stop Chat on one not in it. Check: component test per state.
1. **Name dialog.** Centred, prefilled with the last name used in this browser or the machine's user, shown on every Start Chat and every Accept, Enter confirms (D8). Cancelling after Accept declines. Check: component test.
1. **Start.** The first starter mints a chat UUID, starts the chat and invites the machine whose tab was used. Check: `spec/openlanes/live/chat_spec.rb` asserts a room channel and an invite on the machine channel.
1. **Invite.** Reaches every open page on the invited machine; first answer wins through `SET NX EX 120` on `openlanes:<repo>:chat:invite:<uuid>`; no answer in 60 s, or only `absent` replies, shows "<machine> did not answer"; decline shows "<machine> declined" (D9). Check: hub spec with two simulated pages and one with none.
1. **Invite while in a chat.** The modal says so; accepting leaves the current chat and joins the new one (D4). Check: component test.
1. **Repository scope.** Channels, keys and the page's `GET /api/chat` carry `<repo>`; a second repository on the same Redis never receives them. Check: hub spec with two repo names on one store.
1. **Database isolation.** Every channel name contains `<db>`, since pub/sub crosses databases (Research, finding 2). Check: spec asserts the name for db 1 and db 10 differs.
1. **Messages.** Plain text, line breaks kept, URLs linked, nothing else rendered, 4,000 characters maximum, Cmd-Enter sends (D10). Check: component test for each, and a server-side test that 4,001 characters is refused.
1. **Presence.** Join, leave and idle/back lines appear for others, not for oneself; idle after 60 s without typing, sending or clicking in the panel (D7). Check: hub spec with an injected clock.
1. **Roster.** `join` is answered by `here`; `here` repeats every 20 s; silent for 60 s means left (Implementation choices). Check: hub spec with an injected clock.
1. **Leaving.** Stop Chat leaves at once; a closed stream has 10 s to return before "<name> left"; a stopping server says goodbye for its pages; the chat ends with its last participant (D6). Check: hub spec per case.
1. **Panel.** Header `#D9420B` with black text and the participants' names; body white with `#222`; footer `#B23507` with white text; docked bottom left, collapsed to the left edge; draggable when open; minimise and restore returns to the bottom left (D11). The panel's tab exists only while in a chat, and a page that loads into a chat starts minimised. Check: component tests plus the contrast figures in Research, finding 5.
1. **Shared floating panel.** Drag, minimise and dock live once in `web/src/floating/FloatingPanel.tsx` and both the copilot and the chat use it (D1; `web/src/copilot/Copilot.tsx:151`). Check: both components import it; no second drag implementation (`rg`).
1. **Reload is the same participant.** The page id lives in session storage and goes as `?page=` on the stream. Check: component test or hub spec for a reconnect within 10 s.
1. **CSRF.** `POST /api/chat/:action` follows the usual CSRF rule. Check: request spec for a POST without the token.

## Out of scope

- **Storing or replaying messages.** D2.
- **An avatar URL field.** Named as "later" in the problem statement.
- **Updating the 004 contract's `agentilda:` prefix.** A documentation change in another plan; listed as an open question, not built here.
- **Load testing Puma's SSE threads.** Research, finding 3 flags it unmeasured; it is a deployment limit, not a behaviour of this feature.
- **Redis ACL provisioning.** The code needs `PSUBSCRIBE` on `…:room:*`; whether production restricts it is an operations question.
- **Changing the copilot's behaviour or colours.** Only its use of the shared panel is touched.

## Back end / front end

| Item | `luke-backend` | `rey-frontend` |
| :--- | :--- | :--- |
| Machine menu, menu states | Menu state rules exposed in `GET /api/chat` (who is in, invite pending) | `MachineMenu.tsx`, tab caret and right-click in `App.tsx` |
| Name dialog | none | `dialogs.tsx`, prefill from local storage |
| Start, invite, accept, decline | `Live::Chat`, `POST /api/chat/:action`, invite key | `useChat.ts`, `ChatRoom.tsx` modals |
| Repository scope, db isolation | Channel naming in `chat.rb`, `Subscriber` | none |
| Messages | 4,000-character limit, publish | `ChatPanel.tsx` rendering, links, Cmd-Enter |
| Presence, roster, leaving | Heartbeat, `here`, 10 s grace, goodbye | Idle clock, "is idle / is back" lines, `chat/bus` |
| Panel and shared floating panel | none | `ChatPanel.tsx`, `FloatingPanel.tsx`, `tokens.css` |
| SSE relay and CSRF | `Web::Events`, `Web::App` | `EventSource` with `?page=` |

The pair agrees on one contract before either writes: the event names on `event: chat`, the `POST /api/chat/:action` verbs and bodies, and the shape of `GET /api/chat`. The planner should make that contract its first work unit.

## Open questions

Assumptions I made, and leah's unsettled list. None blocks planning.

1. **Repository scope** is answered: one repository (decided 2026-10-13 by kig, top of this spec). Research's B1 is settled and needs no `blocked.md`.
1. **Production Redis ACL.** Does a user exist that cannot `PSUBSCRIBE` `openlanes:<repo>:chat:*`? Unverified (Research, finding 3). Assumed no. If yes, the hub fails at startup; the planner should have it log and degrade, not crash.
1. **Puma thread budget.** About 64 open pages starve one server (Research, finding 3). Unmeasured. Assumed acceptable for the expected team size.
1. **004 contract prefix.** Update `agentilda:` to `openlanes:` for chat keys, in a follow-up. Assumed yes, outside this plan.
1. **Plan 003 versus 006.** 003 uses Streams for agent mail, 006 uses pub/sub for chat. Assumed intentional; this spec records the difference in Risks.
1. **Is the copilot on `main`?** Research found the component in this branch and did not check `main`. Assumed the placeholder is what ships.
1. **W26 and W29** (`docs/decisions/`) were not opened by research. Assumed they say what 004 and 006 cite.
1. **Web suite.** `just web-test` was not run (Research, finding 6). Assumed it passes; the planner's first unit should run it.
1. **Docking side in the design.** `004/.../design.md:71` shows only a right-edge tab; the left-edge variant is defined by D11 alone. Assumed D11 governs.

## Risks to planning or execution

- **Plan says "never built"; code says built.** Units written as greenfield would duplicate `chat.rb` and the web components. The planner must start from a gap analysis of each in-scope item against the branch.
- **Two Redis conventions on one server.** 003 (Streams, durable) and 006 (pub/sub, lossy) sit side by side. A reader may expect chat messages to survive a restart; they do not (D2).
- **Cross-database pub/sub.** Dropping `<db>` from a channel name would silently join unrelated databases. Keep the isolation spec.
- **Timing specs.** Heartbeat (20 s), roster expiry (60 s), idle (60 s), grace (10 s) and invite expiry (60 s) are slow to test for real. They need an injected clock; wall-clock sleeps will make the suite flaky.
- **Frontend coverage.** The web suite was not run, and the project requires more than 95% coverage; unmeasured for `web/src/chat/`.
- **Colour contrast.** Changing a token breaks the figures in Research, finding 5. Footer ink must stay white.
- **At-most-once delivery.** A message lost between two participants is invisible. This is accepted (D2) and must not be "fixed" inside this plan.

## Conclusion

When this ships, a person on one machine's control room can open a menu on another machine's tab, name themselves, start a chat and invite others on the same repository and Redis. Invitees get a modal on every open page of their machine, and the first answer settles it. Everyone in the chat sees plain-text messages, joins, leaves and idle states in an orange floating panel docked bottom left, separate from the blue copilot, while a hub on each API server relays Redis pub/sub over the existing SSE stream. Nothing is stored: history, avatars and cross-repository chat are not part of it.
