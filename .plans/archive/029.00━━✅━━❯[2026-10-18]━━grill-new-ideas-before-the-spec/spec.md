---
created: 2026-10-16
starts: planning
---

# Grill New Ideas Before the Spec

## What we are trying to achieve

When a person adds a new idea through the page, the page interviews them one question at a time, each with a recommended answer, before `spec.md` is written, and the answers go into the spec. Decided as M6 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`.

## Why it matters

Questions asked while the person is already there replace blocks raised mid-run (M0).

## What already exists

`openlanes start` creates plans from the page (W19); plan 011 interviews only in the terminal at init.

## How to tell it's working?

- Adding an idea on the page starts an interview; each question shows a recommended answer.
- The saved `spec.md` records the decisions.
- Skipping the interview is possible and leaves the spec as today.
