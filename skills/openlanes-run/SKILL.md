---
name: openlanes-run
description: Start the openlanes factory with `openlanes start` (engine plus control room, up until Stop All Local or Ctrl-C, questions answered and plans created on the page), or run openlanes's specialist agents over named plans to a fixed point with `openlanes run <NNN,...>` and clear blocked plans with `openlanes unblock`. Use when the user wants to start, run, resume or finish the agents, build or ship a plan, or unblock a ⭕ / 🛑 plan.
---

# openlanes-run: drive the plans

Load the `openlanes` skill first if it is not in context.

## `openlanes start`: the factory with its control room

`openlanes start` is the way to run the factory for a person. It runs the engine over the whole tree with the control room on, and it does not stop at a fixed point: when a plan blocks, planner's questions included, it idles, shows the questions in **Needs You** on the page, takes the answer from there, drains it, and hands the plan back to its agent. It picks up plans created on the page, by `openlanes create` in another terminal, or edited by hand, rescanning `.plans/` every 5 s (`--rescan`).

```bash
openlanes start              # engine and control room on http://127.0.0.1:11000, browser opened
openlanes start --no-open    # print the URL only
openlanes start --background # detached; prints the URL once the page answers, output in log/openlanes-start.log
openlanes status             # supervisor, engine, web and runs: up or crashed, and the plans by state
openlanes stop               # stops the factory; --all stops every `openlanes run` too
```

- It takes `run`'s flags except `-n` and `--until`, plus `--plan` to narrow it. It needs Redis and refuses without it (exit 69). `--no-web` leaves the page to an `openlanes web` served apart, as `just start` does.
- Every human decision goes through the page: answers, hold, wrap up, stop, models, new plans. **Stop All Local** stops this machine's agents, then its engine and the page; nothing else on the page ends the run. The terminal is output only.
- It never ends on its own, not even once every plan is finished: the page can create the next one. A project with no plans waits for the first. Stop All Local, Ctrl-C or `kill -TERM` end it, with exit 0; agents get the graceful stop and the page goes down with it.
- It is a supervisor over two children, the engine and the page, and restarts whichever crashes (three crashes in five minutes and it gives that one up; `openlanes status` says why). A second `start` in the same project is refused (exit 75) with the running one's URL.
- Start it with `openlanes start --background`, give the user the URL it prints, and leave the answering to them on the page. `openlanes stop` ends it. Steps 1 to 5 below are the scripted, headless alternative.

`openlanes run` loops in rounds. Each round hands every movable plan to the agent its state and lane call for and renames the folder when the agent finishes. When a builder lands a plan at 🟢 Ready for Review, `openlanes` pushes its branch and opens the pull request, titled `[NNN.MM]`; `staff-reviewer` then reviews that pull request. It works only the plans named in its argument, serves no page, and stops at a **fixed point**: a round in which none of them changed state. `--until <state>` stops each plan once it reaches that state (key or emoji). It claims every plan before starting and refuses outright (exit 75), naming the holder, when the factory or another run already holds one. Your job is to start it, watch it, and turn what it stops on into questions for the human.

## 1. Scope and preview

Decide the plans from what the user asked, e.g. `003,005.01`; the whole tree is `openlanes start`'s. Then preview, unless the user has already told you to run:

```bash
openlanes run <NNN,...> -n
```

Each line names a plan, the agent it would get, and the round. Show the user the lines that matter in a few bullets and ask once: "Run these?" One yes covers the whole loop below.

Pick flags from the situation, and read `openlanes run --help` for the rest:

| Situation                                        | Flag                                 |
| ------------------------------------------------ | ------------------------------------ |
| limit machine load or API spend                  | `-j <n>`, `--max-tokens <n>`         |
| the repository has no git                        | `--isolation shared` (serial; see below) |
| one agent is misbehaving                         | `--skip <agent>`                     |
| re-drive one agent with extra guidance           | `--agent <name> --prompt "<text>"`   |
| a short burst, to check one phase                | `--until <state>`, e.g. `--until planned` |
| Redis elsewhere                                  | `--redis-url <url>`                  |

Keep the defaults (`--isolation worktree`, pushing on) whenever the user wants plans reviewed. `--isolation shared` and `--no-git-push` open no pull request, so every plan stops at 🟢 and the reviewer never starts; `openlanes run` warns when that is the case. Use them only when the user asks to keep work local, and say that review waits for a PR they open (`openlanes resync prs` then records it).

## 2. Run it

```bash
openlanes run <NNN,...>
```

A run takes minutes to hours: each agent may take up to 15 minutes per round, over several rounds. Start it in the background and wait for it to exit; it prints its log path at the start (`log/development.log` under the project unless `--log` says otherwise), which is what to read when the user asks how it is going. Avoid polling in a tight loop.

When Redis answers, the run publishes its board there, so a factory's page (`openlanes start`) or `openlanes web` shows it; it serves no page itself. Without Redis the run warns once and goes on with no claims to share; that is not a failure. A refusal naming a holder means the factory or another run already works that plan: leave it out, or stop that one first.

A warning about `ANTHROPIC_API_KEY` (or a similar variable) at the start means every agent will authenticate with that key instead of the user's claude.ai login. Stop and ask before running with it; a stale key fails every agent with `401` after minutes each.

## 3. Read where it stopped

When it exits, `openlanes plans` shows where each plan stands. Sort them into three groups:

- **Advanced to a human gate**: at ✅ Approved & Merged the reviewer has approved, and merging and deploying are the human's. Report the PR links (`gh pr list`).
- **Blocked** ⭕ / 🛑: go to step 4.
- **Unmoved without a block**: an agent failed or ran out of rounds. Read the plan's history with `openlanes state show --plan <NNN>` and say which agent stopped and why. Re-run with a fix (`--agent`, `--prompt`, `--timeout`) only after telling the user what you will change.

## 4. Unblock

For each blocked plan:

1. `openlanes unblock <NNN> -n` prints the open questions.
1. Put them to the human **one at a time**. ⭕ questions are for an engineer, 🛑 for product; say which.
1. Write each answer into the plan's `blocked.md` under `## A<n>`, matching its `## B<n>` (the format is in `openlanes-documents`). An answer counts only when it names who decided (a role is enough), carries today's date, and settles the question. "Leaning towards B" does not count, and the broker will leave it in place.

   ```markdown
   ## A2
   Decided 2026-10-12 by the CTO: rates are read from the vendor feed, never cached.
   ```

1. `openlanes unblock <NNN>` folds the answers into `spec.md` / `plan.md` and renames the folder.

## 5. Loop

Go back to step 2 for the plans that moved. Done when a run ends at a fixed point with every remaining plan at a human gate or blocked on a question the human has chosen not to answer yet. Report:

- [x] plans that reached review or merge, with PR links
- [ ] plans still blocked, and whose decision each waits on
- [ ] plans that failed, and the reason
