---
depends_on: ["005", "014"]
---

# Obi Wan Arbitrator

## What we are trying to achieve

`obi-wan-kenobi-arbitrator` settles the rejection cap, builders' appeals against review findings, and luke-versus-rey API disputes, and checks every `review-passed` verdict at `medium` and `mvp`.

## Why it matters

Without a tie-breaker a disputed plan loops, and a lenient `review-passed` lets real issues reach `main`.

## What already exists

- Decisions M7–M9 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.

## What research needs to settle

- The appeal format in the ledger, and how a struck finding leaves the review.
- What the engine does with each ruling.

## How to tell it's working?

- Each ruling is a dated entry in `state.json` and a PR comment.
- A `review-passed` PR with a critical open finding is downgraded to `review-rejected`.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

