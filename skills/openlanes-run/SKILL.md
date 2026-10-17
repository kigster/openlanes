---
name: openlanes-run
description: Start the openlanes factory with `openlanes start` (engine plus control room, up until Stop All Local or Ctrl-C, questions answered and plans created on the page), or run openlanes's specialist agents to a fixed point with `openlanes run --until-settled` and clear blocked plans with `openlanes unblock`. Use when the user wants to start, run, resume or finish the agents, build or ship a plan, or unblock a ⭕ / 🛑 plan.
---

# openlanes-run: drive the plans

Load the `openlanes` skill first if it is not in context.

## `openlanes start`: the factory with its control room

`openlanes start` is the way to run the factory for a person. It is `openlanes run` with the control room on, and it does not stop at a fixed point: when a plan blocks, palpatine-planner's questions included, it idles, shows the questions in **Needs You** on the page, takes the answer from there, drains it, and hands the plan back to its agent. It picks up plans created on the page, by `openlanes create` in another terminal, or edited by hand, rescanning `.plans/` every 5 s (`--rescan`).

```bash
openlanes start              # engine and control room on http://127.0.0.1:11000, browser opened
openlanes start --no-open    # print the URL only
```

- It takes `run`'s flags except `-n` and `--no-web`. It needs Redis and refuses without it (exit 69).
- Every human decision goes through the page: answers, hold, wrap up, stop, models, new plans. **Stop All Local** stops this machine's agents, then its engine and the page; nothing else on the page ends the run. The terminal is output only.
- It never ends on its own, not even once every plan is finished: the page can create the next one. A project with no plans waits for the first. Stop All Local, Ctrl-C or `kill -TERM` end it, with exit 0; agents get the graceful stop and the page goes down with it.
- Start it in the background, give the user the URL, and leave the answering to them on the page. Steps 1 to 5 below are the scripted, headless alternative.

`openlanes run` loops in rounds. Each round hands every movable plan to the agent its state and lane call for and renames the folder when the agent finishes. When a builder lands a plan at 🟢 Ready for Review, `openlanes` pushes its branch and opens the pull request, titled `[NNN.MM]`; `hansolo-reviewer` then reviews that pull request. With `--until-settled` it stops at a **fixed point**: a round in which no plan changed state. Without it, a run whose control room came up stays up like `start` and never returns, so a scripted run always passes `--until-settled` (or `--no-web`). Your job is to start it, watch it, and turn what it stops on into questions for the human.

## 1. Scope and preview

Decide the scope from what the user asked: the whole tree, or `--plan 003,005.01`. Then preview, unless the user has already told you to run:

```bash
openlanes run -n --until-settled --plan <NNN,...>
```

Each line names a plan, the agent it would get, and the round. Show the user the lines that matter in a few bullets and ask once: "Run these?" One yes covers the whole loop below.

Pick flags from the situation, and read `openlanes run --help` for the rest:

| Situation                                        | Flag                                 |
| ------------------------------------------------ | ------------------------------------ |
| limit machine load or API spend                  | `-j <n>`, `--max-tokens <n>`         |
| the repository has no git                        | `--isolation shared` (serial; see below) |
| one agent is misbehaving                         | `--skip <agent>`                     |
| re-drive one agent with extra guidance           | `--agent <name> --prompt "<text>"`   |
| no browser (CI, a remote shell), or no page at all | `--no-open`; `--no-web` (`openlanes web` can serve it later) |
| port 11000 taken, or Redis elsewhere              | `--port <n>`, `--redis-url <url>`    |

Keep the defaults (`--isolation worktree`, pushing on) whenever the user wants plans reviewed. `--isolation shared` and `--no-git-push` open no pull request, so every plan stops at 🟢 and the reviewer never starts; `openlanes run` warns when that is the case. Use them only when the user asks to keep work local, and say that review waits for a PR they open (`openlanes resync prs` then records it).

## 2. Run it

```bash
openlanes run --until-settled --plan <NNN,...>
```

A run takes minutes to hours: each agent may take up to 15 minutes per round, over several rounds. Start it in the background and wait for it to exit; it prints its log path at the start (`log/development.log` under the project unless `--log` says otherwise), which is what to read when the user asks how it is going. Avoid polling in a tight loop.

When Redis answers, the run also serves the control room (it still ends at the fixed point, because of `--until-settled`) on `http://127.0.0.1:11000` and opens it in the browser: the user watches the board there and can message, interrupt or stop an agent. Without Redis the run warns once and goes on headless; that is not a failure. To get the page, start `redis-server` (or pass `--redis-url`) before the run; `openlanes-setup` has the details.

A warning about `ANTHROPIC_API_KEY` (or a similar variable) at the start means every agent will authenticate with that key instead of the user's claude.ai login. Stop and ask before running with it; a stale key fails every agent with `401` after minutes each.

## 3. Read where it stopped

When it exits, `openlanes status` shows where each plan stands. Sort them into three groups:

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
