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

## Open

