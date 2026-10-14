---
depends_on: ["005", "012", "013"]
---

# Chewie Verifier

## What we are trying to achieve

`chewie-verifier` checks out a PR that passed review, starts the app, follows `## How to test`, and labels it `ok-to-merge` or rejects it with a PNG screenshot. In agent mode the engine then merges; rejections are capped.

## Why it matters

A review reads the diff, but nobody runs the app before it merges.

## What already exists

- Decisions M1, M2, M4, M6, M11 and M14 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.
- `lib/openlanes/execution/executor.rb`: `UNGRANTABLE` keeps `gh pr merge` away from agents.

## What research needs to settle

- Browser automation for the agent (Cypress, Playwright, or Chrome DevTools).
- Converting screenshots to PNG, and committing them through the publisher.
- The engine's merge checks, and the 15-second PR poll in human mode.

## How to tell it's working?

- A PR whose steps pass gets `ok-to-merge`, and in agent mode merges once CI on the PR and on `main` is green.
- A PR whose steps fail gets `review-rejected`, a comment and a PNG screenshot, and the plan goes to 🔴.
- After `max_rejections` the arbitrator is called.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

