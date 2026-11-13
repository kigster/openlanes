---
created: 2026-11-10
starts: planning
depends_on: [none]
---

# Make Openlanes Cheaper

## What we are trying to achieve

Reduce cost and number of tokens.

## Why it matters

Cost is always important.

## What needs to be done

- Trim the per-round prompt. The journal alone is up to about 5k tokens every round, resumed or not. 
  - On a resumed session, send only entries newer than the last round.
- Downgrade deploy-assessor from opus/high to sonnet for diffs under a size threshold.
- Add a dollar budget per plan. Tally counts tokens and the catalogue has rates; refuse a new round once a plan passes its cap, and show it on the board.
