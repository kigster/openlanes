---
created: 2026-10-16
starts: planning
depends_on: ["025.00"]
---

# One Block at a Time

## What we are trying to achieve

A plan's `blocked.md` may hold several questions (B1, B2, …); the page presents, records and drains them one at a time, and the plan unblocks when the last is gone. Each question and its answer go into the asking agent's journal. Decided as M3 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`.

## Why it matters

Several real issues should not cost several blocked rounds, but a person should face one question at a time.

## What already exists

Agents are already told to write `## B1`, `## B2`; `unblocker` drains answered ones and deletes the file when empty; `Snapshot#questions` returns every open question.

## How to tell it's working?

- With three open questions the page shows one; answering it shows the next.
- Each answer is drained on its own, and the plan unblocks only after the last.
- The journal has each B<n> with its A<n>.
