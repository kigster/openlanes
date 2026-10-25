---
created: 2026-10-24
starts: research
depends_on: [none]
---

# Planner Resolves Dependencies

## What we are trying to achieve

luthen-rael writes `depends_on:` while planning and may write that one key in `spec.md` (A6, A17). `ewoki-linker`, the `ready_for_linking` state and the dispatcher gate that sends unlinked plans to it are removed. Any number of dependencies is ordered topologically; only a cycle goes to a person.

## Why it matters

The planner is the first agent to see the implementation, where dependencies show up; a separate agent and state ahead of it decides with less and costs a round.

## What already exists

`agents/ewoki-linker.md`, `agents/luthen-rael-planner.md`, the `ready_for_linking` status and event in `plans/status.rb` and `plans/state_machine.rb`, the ewoki gate in `engine/dispatcher.rb`, `linear/mapping.rb` placements, and plans 008.00 and 008.01.

## What research needs to settle

- Where plans currently in `ready_for_linking` go when the state is removed.
- Which specs assert ewoki behaviour.
