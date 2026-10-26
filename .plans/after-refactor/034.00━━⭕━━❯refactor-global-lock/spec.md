---
created: 2026-10-16
starts: planning
depends_on: ["033.00"]
---

# Refactor Global Lock

## What we are trying to achieve

planner recognises a refactor (from `implementation_requirement: refactor` or the spec), estimates the share of the codebase it touches, and over 50% by files or lines (a setting) writes `execution: global-lock-required`; otherwise `execution: concurrent`. Such a plan starts only when no other plan has an open branch or PR, and nothing else starts until it is merged. Decided as R6 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`.

## Why it matters

A sweeping rename run beside other work leaves conflicts nobody can resolve.

## What already exists

Plans run concurrently; nothing reads `execution:`.

## How to tell it's working?

- A refactor spec over the threshold gets `execution: global-lock-required`.
- The dispatcher starts no new plan while it waits, and the board names what it waits on.
- Nothing else starts until it is merged.
