---
created: 2026-10-24
starts: research
depends_on: ["045.00"]
---

# Tasks Within a Plan

## What we are trying to achieve

A plan too big for one pull request is split into tasks, each its own pull request. Several builders work tasks of one plan in parallel once they have agreed the interfaces, then test the integration. This generalises the luke and rey pair, who build one plan through `contract.md`.

## Why it matters

Large plans today become one oversized pull request built by one agent, which is slow and hard to review.

## What already exists

Work units in `plan.md` written by luthen-rael; the luke-backend and rey-frontend pair and `contract.md`; S18 conflict detection over work units.

## What research needs to settle

Needs its own grilling before research: the task data model, the interface agreement step, how tasks map to pull requests and branches, and how integration is tested.
