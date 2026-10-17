---
created: 2026-10-16
lane: plan
depends_on: ["014.00", "030.00"]
---

# Auto Merge Passing PRS

## What we are trying to achieve

With `merge.by: agent`, the engine merges a PR whose verdict passes, which chewie-verifier labelled `ready-to-merge`, whose CI is green on the PR and on `main`, and which merges clean; then it rebases the other open plan branches onto `main`. Decided as R5 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`.

## Why it matters

Merging without a person is the point of the factory (M0); chewie's verification makes it safe.

## What already exists

M2 says the engine merges and `gh pr merge` stays ungrantable; `Vcs::Refresh` already rebases worktrees.

## How to tell it's working?

- A passing, verified, green, clean PR is merged by the engine.
- A PR missing any one condition is not.
- After a merge, other open plan branches are rebased onto `main`.
