---
created: 2026-11-10
starts: planning
---

# Speed Up Openlanes

## What we are trying to achieve

Make things faster, and stop doing things that are slow but can be done in bulk.

## Why it matters

Speed of software development is one of the metrics a Software Factory is jugded on.

## What needs to be done

- Pre-warm worktrees. 
  - **A fresh worktree "has never run bundle install"; either keep a pool of seeded ones, or share vendor/bundle and node_modules.**
- **Replace 30sec gh polling (Steps::POLL, verification's 15sec) with one batched GraphQL query for all open PRs.**
- Review in two stages. 
  - **Run staff-reviewer first and start security and design only if it passes, or only when the diff touches paths they care about.**
