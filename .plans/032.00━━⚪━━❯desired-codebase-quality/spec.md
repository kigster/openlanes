---
created: 2026-10-16
lane: plan
depends_on: ["030.00"]
---

# Desired Codebase Quality

## What we are trying to achieve

Add `desired_codebase_quality: high | mvp` to `.openlanes.yml`, replacing M5's `build_quality`; ask it at `init`, or once per project in the drawer on the first `review-ok-not-perfect` PR. Under `high` such a PR goes back to luke and rey, who answer every non-✅ comment with a fix or a backed-up rebuttal; under `mvp` it counts as done. Decided as R4 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`.

## Why it matters

It encodes the owner's speed-versus-quality choice once, so nobody is asked per PR.

## What already exists

`Config::KEYS` has no quality key; `build_quality` exists only in decisions.

## How to tell it's working?

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.
