# Decisions: chat between machines

Settled with the author one question at a time, 2026-10-13.

## D1. The copilot panel is built here

Plan 004's copilot (W17) was designed but never built; only its colour tokens shipped. This plan builds the floating panel the chat lives in, following `design/design.md` for dragging and minimising, with the chat's own colours and its dock at the bottom left.

## D2. Pure pub/sub, no history

Messages travel over Redis pub/sub and are not stored. Someone who joins late, reloads the page, or loses the connection for a moment does not see what was said while they were away. Chosen by the author over a Redis Stream that would have kept a backlog.

## Open

- D3. Which element opens the chat dropdown, given that a machine's tab and its status-bar pill already open its board on click.
- D4. How many chats a page can be in at once.
