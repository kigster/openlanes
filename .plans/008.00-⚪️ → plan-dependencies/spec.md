---
depends_on: ["007"]
---

# Plan Dependencies

## What we are trying to achieve

Plans declare `depends_on:` in `spec.md` frontmatter, `Plans::Tree` computes `blocks`, a new `ewoki-linker` agent fills in the key for every plan in every lane, and blockers are assigned first.

## Why it matters

Plans record no dependencies, so the engine can start work whose prerequisites are unfinished and cannot tell which blocked plan holds others up.

## What already exists

- Decisions N6 and N7 in `docs/decisions/decisions-on-plan-folder-naming.md`.
- `lib/openlanes/plans/spec.rb`: spec frontmatter.
- `lib/openlanes/plans/tree.rb`: the decoded tree, the place to build the reverse index.
- `lib/openlanes/engine/runner.rb` and `dispatcher.rb`: assignment order.
- `agents/*.md`: the shape of a new agent; `Agents::Routing` for lanes.

## What research needs to settle

- YAML reads `[034, 045]` as the octal numbers 28 and 37. Either require quoted strings (`["034", "045"]`) or read the raw text; the spec must say which.
- How the engine runs an agent that is not tied to a state, before a plan's first build agent.
- The choice card for more than 3 dependencies, and where the human's answer is stored so it is not raised again.

## How to tell it's working?

- A plan without `depends_on:` never reaches 🟡 Building; ewoki adds the key first, with one reason per dependency in the ledger.
- A plan whose dependency is open stays put while others run.
- `list-plans` shows `blocks 050` on plan 034's row when 050 depends on it, and nothing is written into 034's spec.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

