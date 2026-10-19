# Plan

Four back-end units. `config/queue.yml` is written by U1 only; U2 and U3 read it, so they follow U1. U4 is the integration check.

## Units

1. U1 Dedupe setting: adds `dedupe: true` to `config/queue.yml` and `Queue::Config#dedupe?`.
2. U2 Reject duplicates: `Queue#push` raises `Queue::Duplicate` naming the holder.
3. U3 Worker logging: the worker rescues `Queue::Duplicate` and logs both IDs.
4. U4 Integration check: push the same ID twice through a real queue and worker, nothing stubbed; it must show one job run, one rejection logged with the holder's ID.

## Dependency graph

U1 → U2 → U4, and U1 → U3 → U4. U2 and U3 own disjoint files and may run at the same time.

## Signatures

- `Queue#push(job) → Job`, raises `Queue::Duplicate(id:, holder:)`.
- `Queue::Config#dedupe? → Boolean`.

## Risks

- U2 and U3 both read the setting; if U1 slips, both wait. Nothing else is shared.

> [!NOTE]
>
> [2026-09-04 01:10:00 PM PDT] [ agent: luthen-rael-planner   status: Started, round 1 ]
> [2026-09-04 01:14:30 PM PDT] [ agent: luthen-rael-planner   status: Completed, round 1 ]
