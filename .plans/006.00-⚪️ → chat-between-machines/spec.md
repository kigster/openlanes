# Chat Between Machines

## What we are trying to achieve

People whose machines share one `$REDIS_URL` can chat with each other from the control room.

- The other machines already show in the top right of the header. Clicking one opens a dropdown with **Start Chat**, which becomes **Stop Chat** once a chat is running.
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

- The header lists other machines on the same Redis (`OtherMachines`/node metadata, W26).
- The copilot panel was designed in plan 004 (`design/design.md`, "Header and copilot"; decision W17) but never built: the spec deferred it, and only its colour tokens (`--copilot-head`, `--copilot-body`) are in `web/src/styles/tokens.css`. This plan builds the floating panel.
- The live run already talks to Redis through `Live::Session`, and the page gets server state over SSE.

## What research needs to settle

Open questions are settled one at a time in `decisions.md` before planning.
