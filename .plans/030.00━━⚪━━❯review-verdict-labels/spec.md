---
created: 2026-10-16
lane: plan
---

# Review Verdict Labels

## What we are trying to achieve

Replace M3's verdict labels with `review-rejected` (F90000), `review-vulnerability` (FF0050), `review-ok-not-perfect` (E8E890) and `review-approved` (109a10); keep `ready-for-review` (c2e0c6) and `review-in-progress` (FFBE20); rename `ok-to-merge` to `ready-to-merge` (5319e7). The dispatcher syncs every label's existence and colour on the repo, and computes the verdict by counting the emoji that open the reviewers' comments. Decided as R2 and R3 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`.

## Why it matters

The label is how the engine decides what happens next without a person reading the review.

## What already exists

`Plans::ReviewLabel::ALL` holds the six M3 labels; `openlanes review` sets them; labels are created on first use.

## How to tell it's working?

- Starting on a repo creates or recolours the labels.
- Comments with any ⛔️ or 💣 give `review-rejected` (plus `review-vulnerability` for 💣); more than five 🤔 (a setting, env-overridable) gives `review-ok-not-perfect`; otherwise `review-approved`.
- Only vader's comments may count 💣 and 🔓.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

