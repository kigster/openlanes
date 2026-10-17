---
created: 2026-10-16
lane: plan
---

# Sub Agent Concurrency Cap

## What we are trying to achieve

Every agent gets the `Task` tool with a concurrency cap in its front-matter (default 1, leah 2), overridable per project in `.openlanes.yml` from a 1–4 dropdown in the agent drawer and from `openlanes init`. An agent that exceeds its cap is stopped as on a timeout. Decided as M5 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`.

## Why it matters

Sub-agents let luke and others finish faster; a cap keeps cost and contention bounded without a person watching.

## What already exists

Only leah has `Task` today; the harness counts `subagents` and `delegated` from the stream but enforces nothing.

## How to tell it's working?

- Front-matter `concurrency:` is read, and `.openlanes.yml` `agents.<name>.concurrency` overrides it.
- The drawer dropdown writes the override.
- A second concurrent sub-agent for a cap-1 agent triggers STOP, the kill after grace, and a new round.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

