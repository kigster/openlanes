---
name: openlanes-status
description: "Report where openlanes plans stand: every plan's state and pull requests, the INDEX.md, one plan's agent history from state.json, the messages in its mailbox, or the live control room. Use when the user asks for the status, progress or history of plans, what an agent did or said, wants to watch a run, or wants .plans/INDEX.md regenerated."
---

# openlanes-status: where the plans stand

Load the `openlanes` skill first if it is not in context. Every command here only reads, apart from `index`, which writes one file, and `web`, which serves a page.

| Question                                         | Command                                                     |
| ------------------------------------------------ | ----------------------------------------------------------- |
| every plan, its state, its pull requests         | `openlanes status` (also `list-plans`, `st`)                    |
| a shareable page of every plan                   | `openlanes index` writes `.plans/INDEX.md`; `-o -` prints it    |
| which agents ran on a plan, how long, what model | `openlanes state show --plan <NNN> \| jq '.stages[] \| {agent, round, status, model, seconds}'` |
| what one agent told another                      | `openlanes mail read --plan <NNN> --for <agent>`                |
| what a blocked plan is waiting on                | `openlanes unblock <NNN> -n`                                    |
| which agent picks a plan up next                 | `openlanes run -n --plan <NNN>`                                 |
| watch a run live                                 | the control room URL `openlanes run` printed; for a `--no-web` run, `openlanes web` |
| see the control room with no run, or no Redis    | `openlanes web --demo` (a sample run)                           |

## Reporting

`status` draws a table on STDOUT; pass `-C` when you parse it. Summarise for the user rather than pasting the table:

- a count per state, from the footer line
- each blocked plan, and whether it waits on engineering (⭕️) or product (🅱️)
- each plan in review, with its PR
- anything that looks wrong: a plan whose folder name lags its contents, or a PR without an `[NNN.MM]` title prefix. Both are `openlanes-sync`'s to fix; offer it.

## The control room

`openlanes web` serves the page and its API on `127.0.0.1:11000` (`--port` to move it, `--no-open` to print the URL instead of opening a browser). It shows the board a live `openlanes run` publishes to Redis, so with no run in progress it says so on the page and names `openlanes start` and `openlanes run`, and with Redis down it has nothing to show; `--demo` serves a moving sample instead, from memory when Redis does not answer. Where it finds Redis: `openlanes web --help`.
