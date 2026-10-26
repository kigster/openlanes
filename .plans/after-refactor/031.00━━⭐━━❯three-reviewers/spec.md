---
created: 2026-10-16
starts: planning
depends_on: ["025.00", "030.00"]
---

# Three Reviewers

## What we are trying to achieve

Add `darth-reviewer` (Haiku; Gemini Flash optional) and `security-reviewer` (Sonnet), move `staff-reviewer` to Opus 5.5, and run all three at once on a PR with shared instructions plus each one's focus. Each gets the spec, the plan and the implementers' journal, ignores existing comments, reviews only the diff, opens with "Reviewed by … using … by … at …", and starts each comment with its emoji verdict. Decided as R1 and R2 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`.

## Why it matters

Three angles catch what one reviewer misses, with the cheap model covering the basics and the expensive one the subtle issues.

## What already exists

`staff-reviewer` (Sonnet) handles `ready_for_review` and `in_review` alone.

## How to tell it's working?

- A PR in review gets three reviews, one per agent, each with the header and only allowed emoji.
- Each reviewer's journal is in `state.json`.
- The label follows from the pooled comments (030).
