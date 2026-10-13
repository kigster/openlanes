# Decisions: chat between machines

Settled with the author one question at a time, 2026-10-13.

## D1. The copilot panel is built here

Plan 004's copilot (W17) was designed but never built; only its colour tokens shipped. This plan builds the floating panel the chat lives in, following `design/design.md` for dragging and minimising, with the chat's own colours and its dock at the bottom left.

## D2. Pure pub/sub, no history

Messages travel over Redis pub/sub and are not stored. Someone who joins late, reloads the page, or loses the connection for a moment does not see what was said while they were away. Chosen by the author over a Redis Stream that would have kept a backlog.

## D3. A caret on the machine's tab opens the chat menu

Clicking a machine's tab still opens its board. A small ▾ on the tab, or a right-click on it, opens the menu: Start Chat, Invite to Chat or Stop Chat, whichever applies. The status-bar pills are unchanged.

## D4. One chat per page at a time

A page has one chat panel and is in at most one chat. An invite that arrives while you are in a chat says so; accepting it leaves the current chat and joins the new one. To bring more people in, invite them into the chat you are in.

## Open

