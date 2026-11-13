---
created: 2026-11-12
starts: planning
depth: deep
frontend: true
implementation_suggestions:
  - "A `Plans::Rounds` (or `Engine::RoundLedger`) value object built from `state.json` stages, asked `used(agent, state)`, `next(agent, state)` and `left(agent, state, budget)`; the dispatcher keeps no round counter of its own"
  - "Record the state a round ran in on each stage (`from`), since today's stages carry `to` and `state: null`"
  - "Classify a failed start with the same test `Executor#lost_session` uses: no tokens in, none out, no tool call, not killed"
  - "Land after pull request 205 (the dispatcher split), in `Dispatcher::Start`, `Settle` and `Assign`, to avoid rebasing a 2,500-line file twice"
implementation_requirements:
  - "The round number an agent is told, the round it signs, and the round the board shows are the same number, read from one place"
  - "A restart of the engine never lowers a round number and never hands out a round that was already spent"
  - "An invocation that failed before spending anything is recorded, is shown in the log, and does not count against the agent's rounds"
  - "No change to the state machine topology or to the Status vocabulary"
  - "Every changed Ruby file stays at or above 95% coverage; no file is added to `.rubocop_todo.yml`"
task-completed-when:
  - "Stopping and restarting `ol start` mid-plan continues each agent at its next round number, with the rounds left unchanged"
  - "An agent whose `claude` call fails to authenticate three times in a row still has every round it started with"
  - "After a failed authentication the engine starts no further agent on that CLI until a probe succeeds, and says so in its idle line"
  - "A signature for the round the agent was told is accepted; `no closing ledger line` is never reported for a round that signed"
  - "Each agent definition states `rounds:`, and the defaults are written down in one table"
  - "The three choices on a request say what each one grants"
---
# Durable Round Ledger

## What we are trying to achieve

One owner for how many rounds an agent has used on a plan, so the engine, the agent and the page agree, and a restart or an outage costs nothing.

Today that fact lives in three places that disagree:

- `Dispatcher#@history`, in memory, emptied by every engine start. `Dispatcher#start` numbers a round from it (`count + 1`), and `eligible?` and `out_of_rounds` budget from it.
- `state.json` `stages`, on disk, which the agent reads through `openlanes state show`.
- `Engine::StateFile`, the restart record, which `Recovery::Reattach` uses to give back the round number of an agent that was mid-run, and nobody else's.

## Why it matters

Observed on 2026-11-12, on this repository's own plans:

- **A signed round thrown away.** After a restart the engine told `frontend-coder` on 040.00 it was on round 1. `state.json` already held rounds 1, 1, 2 and 3. The agent wrote "Two prompts for this plan arrived back to back, one saying round 3 and one saying round 1. I signed as round 3." `Dispatcher#settle` drops a ledger entry whose round is not the task's, so a 47 second run that signed `Almost completed` was recorded as `no closing ledger line; Interrupted; no rounds left`.
- **Rounds burned by an outage.** `claude` failed with `OAuth session expired` in two seconds. `settle` records any failed result as an `Interrupted` round, so each failure spent a round, the one automatic extension was spent the same way, and the request went to a person. This happened on seven plans at once.
- **A budget of one.** No file under `agents/` sets `rounds:`, and `Agents::Registry` clamps a missing value to 1. Every agent gets one round per state per engine process. Extensions count only grants settled since the run started (`Extensions#rounds`, `@since`), so each restart silently hands out a fresh round and then asks again.
- **A person asked the same question all afternoon.** The operator's words: "all I am doing is extending Rounds by 1". The three choices read "Extend Rounds by 1", "Extend Time by 10 minutes", "Extend Time by 20 minutes"; on a rounds request all three grant a round, which the labels do not say.

## What already exists

- `Plans::PlanState#stage!` writes one stage per agent and round, with `status`, `to`, tokens and the session. `Plans::Ledger.last_for` reads the agent's signature.
- `Engine::Extensions` holds requests and grants in `state.json` (`extensions`), and `#rounds` counts them.
- `Executor#lost_session` already tells "failed before spending anything" from a real failure, for a resumed session only.
- `Execution::Control.pause!` and `paused?` stop new dispatch while Redis is away (W32); `next_dispatchable` already honours it.
- `Adapters::Probes` asks `claude auth status --json` at start-up and knows `not signed in`.
- Pull request 212 shows "Round 2 of 3" on the tile and counts granted rounds in the total; pull request 204 waits out a 429 or 529 inside one attempt; pull request 205 splits the dispatcher into steps.

## Scope

In:

1. Round numbers and rounds used are derived from `state.json` stages for the plan's current state; the in-memory history goes, or becomes a cache of that reading that a restart rebuilds.
1. A stage records the state the round ran in.
1. A failed start (nothing spent) is a stage with a status of its own that no budget counts.
1. An authentication failure pauses dispatch for that CLI, with the reason in the idle line and on the page, until its probe passes; other CLIs keep working.
1. `rounds:` in every agent definition, with a documented default per phase, and extension grants that survive a restart for the visit to the state they were granted on.
1. Choice labels that say what is granted: for a rounds request, "One more round", "One more round with 10 extra minutes", "One more round with 20 extra minutes".

Out:

- Splitting any class for size alone; that is 045.00's.
- Rate limits and overload (pull request 204).
- The reviewer labels and the risk assessor's place in the round (031.00).

## Open questions for planning

- Whether the round budget is per visit to a state (a plan sent back from review starts fresh) or for the plan's life. The evidence favours per visit, keyed by `moves`.
- What the defaults are. A starting point: coders 3, planner and spec-writer 2, reviewers and researcher 2, unblocker 1.
- Whether a failed start retries on its own after a backoff, and how many times before it asks.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

## How to tell it's working?

- bundle exec rspec spec/openlanes/engine spec/openlanes/plans spec/openlanes/execution
- bundle exec rspec spec/openlanes/engine/restart_rounds_spec.rb
- cd web && npx vitest run && cd .. && bin/web-e2e
