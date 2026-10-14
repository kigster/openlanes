---
depends_on: ["010"]
---

# Init Interview

## What we are trying to achieve

`lanes init` interviews in the terminal: who merges, build quality, then the stack, with AI extraction from a free-text description, and porting when an existing stack is to be replaced. `--reconfigure` re-runs it.

## Why it matters

Merge mode, build quality and stack are project-wide decisions that every later agent depends on.

## What already exists

- Decisions M4, M5, M16 and M18 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.
- `lib/openlanes/cli/init/`, `lib/openlanes/support/config.rb` (`.openlanes.yml`).

## What research needs to settle

- Stack detection: which files identify which stacks.
- The questionnaire itself, as an inquirex flow.
- The `stack:` summary in `.openlanes.yml` and the shape of `docs/decisions/stack.md`.

## How to tell it's working?

- In an empty folder with `ANTHROPIC_API_KEY` set, describing "a web Minesweeper with a leaderboard" skips the questions the description answered.
- Without a key, `init` says so once and asks everything.
- `.openlanes.yml` ends up with `merge.by`, `build_quality` and `stack`; `--reconfigure` shows what changed before saving.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

