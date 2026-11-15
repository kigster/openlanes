---
created: 2026-11-01
starts: planning
depends_on: [none]
---

# Abandon Discard Trash Plans

## What we are trying to achieve

`ol plans abandon|discard|trash NNN.MM ... [--reason TEXT]` takes plans out of the active list from whatever state they claim, records why in `<state>-reason.md`, and rewires dependents around them. `ol resync dirs` does the same for a reason file written by hand.

The specification is `docs/decisions/decisions-on-plan-abandon-discard-trash.md`.

## Why it matters

Projects carry stale, blocked or half-finished plans for features built outside OpenLanes, and those plans stand in the way of real work.

## What already exists

❌ Discarded and `.plans/abandoned/`, `Plans::Dependencies`, `Lifecycle::Resync::Dirs`, `OpenLanes.move_directory`.

## What research needs to settle

Nothing. `starts: planning` skips research.
