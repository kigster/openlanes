---
created: 2026-10-16
starts: planning
depends_on: ["024.00"]
---

# Agent Memory Journal

## What we are trying to achieve

Each agent keeps an ordered journal of `todo`, `done`, `decision`, `question`, `override` and `note` entries, printed as one-line JSON in its own output and written by the dispatcher into `state.json` under `memory.<agent>.rounds.<n>`. The next round's prompt includes the previous round's journal. Decided as M2 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`.

## Why it matters

A killed or timed-out agent today leaves only a thin resume record, and its successor redoes work. The journal keeps decisions and progress as they happen, with one writer, so a pair working at once cannot collide.

## What already exists

`PlanState` already locks every write; `Transcript` and `Adapters::Stream` already read every agent's stream; `last-known-state` holds a one-line resume record.

## How to tell it's working?

- An entry printed by the agent appears in `state.json` under its agent and round, in order, and validates against the schema.
- An `override` names the entry number it overturns.
- A killed agent's already-printed entries are kept.
- Round n+1's prompt contains round n's journal, with or without `--resume`.
- Reviewers (031) and luke and rey answering a review journal the same way.
