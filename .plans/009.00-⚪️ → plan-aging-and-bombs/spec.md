---
depends_on: ["008"]
---

# Plan Aging and Bombs

## What we are trying to achieve

Blocked plans age. One that others depend on becomes 💣 after 7 days unanswered and halts the run; one nobody depends on moves to `deferred/` after 14 days. The control room shows a split notice with Respond and Pause and Discuss.

## Why it matters

In equilibris-app 9 of 14 open plans were blocked, some for months, and nothing forced a decision.

## What already exists

- Decisions N8–N10 in `docs/decisions/decisions-on-plan-folder-naming.md`.
- The `blocks` index from plan 008.
- `lib/openlanes/lifecycle/unblocker.rb` and `lando-broker`: answering blocks.
- The copilot panel (PR #7), which Pause and Discuss opens.

## What research needs to settle

- The 💣 state: its event in the `aasm` block, its invariant, its place in `linear/mapping.rb`.
- `plans.aging_since` in `.openlanes.yml`, and the clock starting from the date a plan became blocked.
- How `run` halts and how `--ignore-bombs` and "Resume anyway for 24 h" lift the halt.

## How to tell it's working?

- With `aging_since` set to today, nothing ages. Backdate it, and a blocked plan with dependents turns 💣 and `lanes run` exits non-zero naming it.
- The notice shows `blocked.md` on the left and an answer box on the right; Respond writes into `blocked.md`, and work resumes on the next round.
- A blocked plan with no dependents moves to `deferred/` after 14 days.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

