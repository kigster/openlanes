---
created: 2026-10-16
starts: planning
---

# Resume Sessions Across Rounds

## What we are trying to achieve

An agent's next round on the same plan state resumes its previous session (`--resume <id>`) instead of starting from an empty context. Decided as M1 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`.

## Why it matters

A fresh session per round throws away everything the agent learned, so rounds take longer and cost more tokens than they need to. M0: fewer stalls, less waste.

## What already exists

`Adapters::Claude#resumes?` is true and `Handle#session` already records the session id, but `--resume` is only used for compaction inside one round (`executor.rb` `resumption`). Autocompact is already 40% (`Adapters::AUTOCOMPACT`). codex and pi report `resumes? = false`.

## How to tell it's working?

- Every round's session id is stored in its `stages` entry in `state.json`.
- Round 2 of the same agent on the same state, in the same checkout, is invoked with `--resume <round 1 session id>`.
- A plan that moved to another state, or a session that cannot be found, starts fresh, and the log says why.
- An adapter that cannot resume starts fresh as today.
