# Plan

1. U1 Remove the last reader of `legacy_email`, then drop the column.

## Merge risk, PR #21

**Verdict:** manual

**Triggers:** schema and data: `db/migrate/20261020120000_drop_legacy_email.rb:3` drops `users.legacy_email`; the old code still running during the deploy overlap may read it.

**Signals:** none.

**Unplanned files:** none.

**Rollback:** a revert does not restore the dropped data; it needs a restore of the column from the last backup. Without a backup the drop is permanent.

**For the human:**

- Confirm a backup of `users.legacy_email` exists before merging.
- Confirm no deployed code reads the column.

> [!NOTE]
>
> [2026-10-20 10:00:00 AM PDT] [ agent: palpatine-risk-assessor   status: Started, round 1 ]
> [2026-10-20 10:03:00 AM PDT] [ agent: palpatine-risk-assessor   status: Completed, round 1 (manual) ]
