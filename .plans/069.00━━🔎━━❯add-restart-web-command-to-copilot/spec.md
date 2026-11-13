---
created: 2026-11-12
starts: research
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

