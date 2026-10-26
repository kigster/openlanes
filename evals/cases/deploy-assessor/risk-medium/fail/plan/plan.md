# Plan

1. U1 Remove the last reader of `legacy_email`, then drop the column.

## Merge risk, PR #21

**Verdict:** auto

**Triggers:** none.

**Signals:** none.

**Unplanned files:** none.

**Rollback:** `git revert` the merge.

> [!NOTE]
>
> [2026-10-20 10:00:00 AM PDT] [ agent: deploy-assessor   status: Started, round 1 ]
> [2026-10-20 10:01:00 AM PDT] [ agent: deploy-assessor   status: Completed, round 1 (auto) ]
