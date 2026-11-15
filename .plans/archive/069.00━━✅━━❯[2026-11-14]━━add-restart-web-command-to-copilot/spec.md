---
created: 2026-11-12
starts: research
depends_on: [none]
---

# Add Restart Web Command to Copilot in Control Room on the bottom right

## What we are trying to achieve

Let the human operator type `/restart-web` into the copilot chat in the control room, and have the web component shutdown, rebuild web assets, and restart. This can be useful whenever some features are added to the web control room.

The copilot is documented as read-only (`README.md`, agents table: `copilot`, "read-only"), but this is not the case  anymore since it already accepts "/stop" "/restart" and "/concurrency" commands. 

Therefore, please update README, and enumerate commands that copilot accepts (this list will only grow) together with the syntax, any arguments each command takes and exactly what it does.

Command `/restart-web` does not have any arguments, it simply tells dispatcher to shut it down, rebuild web assets, and restart it. 

## What already exists

- `bin/lanes-e2e:5` and `justfile:89`: a Cypress run types `/concurrency`, `/stop` and `/restart` into the copilot while real agents work. These are the only references to `/restart` in the repo. The e2e script is the existing test that would exercise it.
- `lib/openlanes/live/copilot.rb`, `lib/openlanes/live/copilot/operator.rb`, `copilot/brief.rb`, `copilot/cards.rb`: the copilot code. `operator.rb` is the likely home for a slash command. Start by checking whether it already parses `/stop` or `/concurrency`; I did not open these files.
- `lib/openlanes/web.rb:10`: a comment saying a restarted web server loses nothing, so the web server restart is harmless.
- `lib/openlanes/apps/runner.rb` (`ACTIONS = %w[restart stop]`) and `lib/openlanes/apps/supervisor.rb` (`restart`): the restart action for preview apps, a model for a restart request coming from the page.
- `web/src/preview/PreviewToolbar.tsx` ("Restart backend"): the page-side restart button and its tests: IRRELEVANT HERE. This command restarts the BACKEND, not the web UI.
- `README.md` (`openlanes start`): the supervisor already restarts the engine or the page when either crashes, and gives up after three crashes in five minutes (`skills/openlanes-run/SKILL.md`). HOWEVER IT DOES NOT REBUILD WEB ASSETS, if they changed. **This command must.**
- `README.md` (agents table): the `copilot` agent is stated to be read-only and runs on haiku/low. THIS IS NO LONGER THE CASE, and README must be updated. The agent should run on Sonnet, and it should be able to report on status of each command aimed at a worker, and also report on general stats, similar to what's printed into the log when OpenLanes stops.
- `lib/openlanes/adapters/base.rb:99`: mentions the copilot keeping resume support (W17).
- `.rubocop_todo.yml` lists the copilot files under several cops, so touching them means paying down or keeping those exemptions.

## Decisions

- Question: does `/restart` restart the web page, the engine, or both? 
  Answers: `/restart NNN` starts a plan again when it is on the board with no agent, for example a lane that lost its agent. It does not answer questions or change the plan's documents. You type it in this panel, and the engine runs it. 
- NOTE: `/restart NNN` is a command to restart a particular plan's worker if they are stuck.
  NOTE: `/restart-web` is a completely different command that ONLY restarts the control room, and NOTHING ELSE



## Research

The Dispatcher already knows how to start the web control room. It might need to learn how to build any assets for the control room (CSS/JS/images) that may have changed.


## Decisions from blocked.md

### B1 (answered) — The supervisor carries out the web restart

The engine and dispatcher have no handle on the web process; the supervisor started by `openlanes start` owns it. Who stops, rebuilds and restarts it?

### D1 (decision) — The supervisor carries out the web restart

Answered:

- 2026-11-13
- By hermes

`/restart-web` goes to the engine as usual; the engine asks the supervisor (through its registration or PID files), and the supervisor stops the web child, runs the build, and starts it again.

### B2 (answered) — Refuse `/restart-web` when no supervisor runs

`openlanes web` can run alone, with nothing to start it again after a kill.

### D2 (decision) — Refuse `/restart-web` when no supervisor runs

Answered:

- 2026-11-13
- By hermes

Refuse with a clear reply: "`/restart-web` needs `openlanes start`; no supervisor is running."

### B3 (answered) — Build in the gem's `web/`, restart even if the build fails

`npm run build` needs Node and the page sources, which an installed gem may lack.

### D3 (decision) — Build in the gem's `web/`, restart even if the build fails

Answered:

- 2026-11-13
- By hermes

Run `npm run build` in the gem's `web/` directory. If Node or the sources are missing, or the build fails, keep the old page, restart the server anyway, and report the failure in the reply.

### B4 (answered) — Copilot moves to Sonnet but stays proposal-only

The brief asks for Sonnet, per-command status reports and run statistics, which touches `agents/copilot.md` and the read-only boundary in `operator.rb`.

### D4 (decision) — Copilot moves to Sonnet but stays proposal-only

Answered:

- 2026-11-13
- By hermes

Change only the model to Sonnet and the README wording. The copilot still acts only through the slash grammar and buttons, and gains read-only commands that print status and run statistics. It does not send commands on its own.

______________________________________________________________________


## Framing

Two ways to frame the problem:

1. **A new slash command.** `/restart-web` is one more word in `Slash.parse` (`lib/openlanes/live/copilot/slash.rb:35`), one more `Command` kind, one more handler in `Commands` (`lib/openlanes/live/commands.rb:745` shows the shape of `restart_plan`).
2. **A way for the engine to reach its supervisor.** The command is trivial; the missing piece is that the engine has no handle on the web process, which the supervisor owns (`lib/openlanes/supervision/supervisor.rb:15`, `Slot#pid`). Nothing today goes from engine to supervisor.

Picked **2**, with 1 as its front door: the slash plumbing is copy-and-adapt, and the only new design is the engine-to-supervisor request and the build step. The README work (list every command, fix the "read-only" wording) rides along.

## Goal

A person typing `/restart-web` in the control room's copilot panel gets the control room stopped, its page rebuilt (`npm run build` in the gem's `web/`), and started again, with a reply in the panel saying what happened, including a build failure. The README lists every slash command with its syntax, arguments and effect, and no longer calls the copilot read-only. The copilot runs on Sonnet and can print status and run statistics through read-only commands.

## Non-Goals

- Restarting the engine, or any plan's worker. `/restart NNN` already restarts a plan's worker; `/restart-web` touches the control room and nothing else.
- Restarting the preview apps' backend (`web/src/preview/PreviewToolbar.tsx`, `lib/openlanes/apps/`): unrelated.
- Letting the copilot agent send commands by itself. It still proposes; the person types a slash command or presses a button (decision D4).
- A restart when no supervisor runs, for example `openlanes web` alone (decision D2): it is refused.
- Hot reload, watching `web/src`, or building anything but the page.
- Changing the supervisor's crash policy (three crashes in five minutes).
- Installing Node, or building when the gem ships no sources.

## In scope

1. `/restart-web` parses with no arguments and becomes an engine command. Check: `Slash.parse("/restart-web", id:)` returns a `Command`; `/restart-web 3` returns `Help` saying it takes no arguments; the `USAGE` text lists it.
2. The engine handler asks the supervisor to restart the web child (decision D1). Check: a spec with a fake supervisor records exactly one request.
3. The supervisor stops the web child, runs `npm run build` in `Web::GEM_ROOT/web` (`lib/openlanes/web.rb:19`), then starts the web child again on the same port. Check: a `Supervisor` spec using the `Host` seams shows stop, build, start in that order, and the new pid in the slot.
4. A missing `npm`, missing `web/package.json`, or a failing build leaves `web/dist` as it was, still restarts the server, and says why in the reply (decision D3). Check: specs for each of the three.
5. A restart is not counted as a crash by `Crashes`, and does not trip the three-in-five-minutes give-up. Check: spec restarting four times in a row.
6. With no supervisor running, the reply is "`/restart-web` needs `openlanes start`; no supervisor is running." (decision D2). Check: spec for the refusal, and for `--no-web` where no web child exists.
7. The reply goes to the copilot panel as the existing `Refusal` / reply turn does for `/stop`. Because the page's own server restarts, the reply must reach the person after the page reconnects. Check: e2e step that types `/restart-web` and sees the reply and a working page afterwards.
8. `set_model` of the copilot changes from `haiku` to `sonnet` in `agents/copilot.md` (frontmatter `model:`), effort stays unless the planner finds a reason. Check: `Agents::Profile.resolve` for copilot returns Sonnet; the roster spec and README table agree.
9. Read-only slash commands that print status and statistics (decision D4). Names and output are open questions 1 and 2; whatever is chosen must read from Redis and the plan folders only and never queue an engine command. Check: specs that the command queues nothing and prints the expected text.
10. README: the agents table row for `copilot` (`README.md:322`) drops "read-only" and "haiku/low"; a new section lists every slash command (`/stop NNN`, `/restart NNN`, `/concurrency N`, `/restart-web`, plus item 9's) with syntax, arguments and exact effect. Check: a spec compares the README list with `Slash`'s table, so the two cannot drift (see Risks).
11. The doc comments that say the copilot is read-only (`slash.rb:5`, `operator.rb:25`, `agents/copilot.md` description) are corrected. Check: `rg "read-only" lib agents README.md` shows only accurate uses.
12. `just lint` and `just test` stay green; any `.rubocop_todo.yml` entries for touched copilot files are kept or paid down.

## Out of scope

- A confirmation button before restarting: the person typed the command on purpose, as with `/stop`.
- Restarting the web from the CLI (`openlanes restart-web`): no one asked; add later if wanted.
- Rebuilding on every `openlanes start`: separate concern, slows each start.
- Making the copilot agent act on its own: decided against (D4).
- Remote nodes: the command acts on this machine's supervisor only.

## Back end / front end

| Item | Back end (`backend-coder`) | Front end (`frontend-coder`) |
| :-- | :-- | :-- |
| 1 slash parse | `slash.rb`, `command.rb` (`KINDS`) | none; the page parses nothing (`slash.rb:12`), though its hint text, if it has one, lists the commands |
| 2 engine handler | `commands.rb`, a small new engine-to-supervisor request | none |
| 3 stop, build, start | `supervision/supervisor.rb` (and a builder class beside it) | none |
| 4 build failure | same | none |
| 5 crash accounting | `supervision/crashes.rb` or `slot.rb` | none |
| 6 refusal | `commands.rb`, `supervision/registration.rb` lookup | none |
| 7 reply after reconnect | reply written to the stream before the web stops, or after it is back | Cypress step in `bin/lanes-e2e`; page must survive the server restart (check for a reconnecting event stream) |
| 8 Sonnet | `agents/copilot.md` | none |
| 9 status and stats | `slash.rb`, a new read-only responder | the copilot panel's hint, if it lists commands |
| 10-12 docs, comments | README, comments | none |

## Open questions

Already decided, from `blocked.md`: who restarts (the supervisor, D1), no supervisor (refuse, D2), build failure (restart anyway and report, D3), copilot model and boundary (Sonnet, proposal-only, read-only status commands, D4). Still open:

1. **Names and arguments of the read-only commands.** Assumed `/status` (all plans) and `/status NNN` (one plan's workers and the state of each command sent to them), and `/stats` (the figures printed when OpenLanes stops, which `Engine::Tally#render` at `lib/openlanes/engine/tally.rb:86` already produces). Not anchored in the brief; the planner may rename.
2. **Where `/stats` gets its numbers while the run is live.** `Tally` belongs to the engine; the API server only has Redis (`live/meter.rb`). Either the engine publishes the tally to Redis, or `/stats` is a command the engine answers. Not settled from the code.
3. **How the engine reaches the supervisor.** Assumed a signal (for example USR2) sent to the pid in the supervisor's PID file, verified with `Probe#verified?` (`supervision/pid_file.rb`), with the supervisor acting on its next tick. `USR1` is already used for agents (`supervision/agent_sweep.rb:32`). A file or Redis flag would also work. Settle in `plan.md`.
4. **Does "the engine asks" mean the engine process?** Under `openlanes start`, the engine is a child of the supervisor, so the signal goes to its parent. Not checked: whether `openlanes engine` run alone, beside a separate `openlanes web`, has a supervisor to ask. Per D2 the answer is a refusal.
5. **Which reply the person sees.** The API server dies with the web child, so a reply written afterwards must live in Redis. Whether the copilot panel redraws replies written while the page was away is unchecked.
6. **Does `npm run build` need the gem's `web/` to be writable?** An installed gem under a root-owned directory fails the build; that falls under D3 (keep the old page, report).
7. **How long to wait for the build.** No timeout is stated; assumed a few minutes, to keep the supervisor's tick from blocking (so the build runs in a thread or child).

## Risks to planning or execution

- **Supervisor tick blocks on a build.** `Supervisor#watch` ticks every 0.2s (`supervisor.rb:23`); a synchronous `npm run build` would freeze crash handling for the engine too. The build must run off the tick.
- **A restart looks like a crash.** `reap` checks the PID file to tell a crash from a stop (`supervisor.rb:132`); a deliberate stop must leave the supervisor's accounting clean, or four restarts end the web for good.
- **README and grammar drift.** The list in README is hand-written unless a spec ties it to `Slash`. The code repeatedly records that duplicated tables go stale; use a spec, or derive the list from `Slash`.
- **Sonnet costs more per chat message** than haiku; every message resumes a session. Accepted by D4, noted for the README.
- **e2e is slow and spends tokens** (`bin/lanes-e2e`, `justfile:76`); the restart step may be better covered in the demo-mode Cypress run.
- **`.rubocop_todo.yml` lists paths**; moved or new files need entries or none.
- **The page needs `web/dist` built** before `just test` (`justfile:127`); the build step must not break a checkout's `web/dist` on failure.

## Conclusion

When this ships, `/restart-web` in the copilot makes the engine ask the supervisor to stop the web child, rebuild `web/dist`, and start it again, refusing when no supervisor runs and reporting a failed build while restarting on the old page. The copilot runs on Sonnet and offers read-only status and statistics commands. The README lists every slash command with its syntax and effect, and no longer says the copilot is read-only.
