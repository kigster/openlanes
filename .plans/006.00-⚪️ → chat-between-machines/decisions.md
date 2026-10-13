# Decisions: chat between machines

Settled with the author one question at a time, 2026-10-13.

## D1. The chat gets its own floating panel, sharing code with the copilot's

Plan 004's copilot (W17) was designed but never built; only its colour tokens shipped. The chat's panel follows `design/design.md` for dragging and minimising. The drag, minimise and dock behaviour is written once and used by both panels (see D11); whichever of the copilot or the chat is built first writes it.

## D2. Pure pub/sub, no history

Messages travel over Redis pub/sub and are not stored. Someone who joins late, reloads the page, or loses the connection for a moment does not see what was said while they were away. Chosen by the author over a Redis Stream that would have kept a backlog.

## D3. A caret on the machine's tab opens the chat menu

Clicking a machine's tab still opens its board. A small ▾ on the tab, or a right-click on it, opens the menu: Start Chat, Invite to Chat or Stop Chat, whichever applies. The status-bar pills are unchanged.

## D4. One chat per page at a time

A page has one chat panel and is in at most one chat. An invite that arrives while you are in a chat says so; accepting it leaves the current chat and joins the new one. To bring more people in, invite them into the chat you are in.

## D5. Any participant may invite

Everyone in a chat sees **Invite to Chat** on the machines that are not in it yet. There is no host, which fits the help dialog's "nobody can be kept out".

## D6. Stop Chat leaves; the chat ends with its last participant

**Stop Chat** takes you out of the chat. The others see "<name> left" and carry on. Closing the tab counts as leaving. The chat ends when its last participant leaves.

## D7. Idle means 60 seconds without typing, sending or clicking in the chat

Typing in the chat, sending, or clicking or focusing inside the panel resets a 60-second clock. When it runs out, the others see "<name> is idle"; the next touch shows "<name> is back".

## D8. The Name dialog is prefilled, and still asked every time

The dialog appears on every Start Chat and every accepted invite, prefilled with the name last used in this browser, or with the machine's user on first use. Enter confirms.

## D9. An invite reaches every open page on the machine, and expires after 60 seconds

Every control-room page open on the invited machine shows the modal; the first to accept or decline settles it for all of them. With no answer within 60 seconds, or no page open there, the inviter sees "<machine> did not answer".

## D10. Messages are plain text with clickable links

Line breaks are kept and URLs become links; nothing else is rendered. A message holds up to 4,000 characters.

## D11. Two panels, never mixed up

The AI copilot (c3po-operator, W17) and the chat with other machines are two separate panels, and both can be open at once:

- the copilot docks at the bottom right in its blue (`--copilot-head`, `--copilot-body`), minimising to its tab on the right edge;
- the chat docks at the bottom left in orange (`#D9420B` header, white body, darker orange footer), minimising to its tab on the left edge.

Their colours stay distinct so one is never taken for the other. Chosen by the author over one panel with an AI tab and a Chat tab.

## Left to the planner

How the page reaches pub/sub (a browser cannot talk to Redis, so the API server subscribes and relays over SSE, and sends arrive by POST), the channel names, and the floating panel's component boundaries.

## Implementation choices

Made while building, 2026-10-13. None changes D1–D11; they fill in what was left to the planner.

- **Transport.** Each API server holds one `Live::Chat` hub with one Redis subscription of its own. It relays to its pages over the existing `GET /api/events` stream (`event: chat`, no `id:`), and pages act by `POST /api/chat/:action` under the usual CSRF rule. The page names itself with an id kept in session storage (`?page=` on the stream), so a reload is the same participant.
- **Channels.** `openlanes:<repo>:chat:<db>:room:<chat uuid>` per chat (each server takes them all through one `PSUBSCRIBE …:room:*`), and `openlanes:<repo>:chat:<db>:machine:<node id>` per machine (`SUBSCRIBE`). Redis delivers `PUBLISH` across databases, so the database number is in every name: nodes on different databases never hear each other. The first answer to an invite is a key, `openlanes:<repo>:chat:invite:<uuid>`, `SET NX EX 120`.
- **Roster without storage.** A joiner publishes `join`; every server with a participant there answers `here`; each server repeats `here` every 20 s, and a participant not heard from in 60 s is shown as having left. Nothing said is kept (D2).
- **Leaving.** Stop Chat leaves at once. A page whose stream closes has 10 s to come back (a reload or a blip) before the others see "<name> left" (D6). A server that stops says goodbye for its pages.
- **Invites.** Start Chat on a machine's tab starts the chat and invites that machine. Every server for the invited machine shows the modal on all its open pages; one with no page answers `absent`, and when every server that heard the invite is absent, or none heard it, the inviter sees "<machine> did not answer" at once rather than after 60 s. A decline tells the inviter "<machine> declined". Cancelling the Name dialog after Accept declines.
- **Menu.** Outside a chat: Start Chat. In one: Stop Chat on a machine already in it; Invite to Chat (greyed while an invite waits) and Stop Chat on one that is not.
- **Panel.** The tab exists only while the page is in a chat. Starting or joining opens the panel; a page that loads into a chat starts minimised. Your own idling is not announced to you. The footer's few words are white: black on the darker orange is under 4.5:1.
- **Component boundaries.** `Live::Chat` (hub), `Live::Subscriber`/`MemorySubscriber` (pub/sub on both stores), `Web::Events` (relay), `Web::App` (routes). On the page: `chat/useChat` (state), `chat/bus` (stream to state), `ChatRoom` (provider, dialogs, panel), `MachineMenu`, `ChatPanel` on the shared `FloatingPanel`.
