---
created: 2026-10-16
lane: plan
depends_on: ["025.00"]
---

# Agent Asks for More Time

## What we are trying to achieve

Before an agent's clock runs out the dispatcher asks it whether it needs more time, and grants it in 5-minute chunks (a global setting) up to 30 minutes in total; after that the agent is interrupted and a new round resumes its session. A person sees the `X<n>` card (PR #62) only after the 30 minutes or when the agent is out of rounds. Decided as M4 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`, amending E1 in `docs/decisions/decisions-on-limit-extensions.md`.

## Why it matters

The agent knows best whether it is nearly done; asking it first keeps a person out of the loop (M0).

## What already exists

PR #62 adds `Engine::Extensions`, `X<n>` requests in `state.json`, a live `Handle#extend!`, and an automatic 10 minutes that this plan replaces.

## How to tell it's working?

- An agent that answers yes gets 5 more minutes on its live clock, up to 30 in total.
- At 30 minutes it is interrupted and its next round resumes the session.
- The `X<n>` card appears only after the cap or when rounds are exhausted.
