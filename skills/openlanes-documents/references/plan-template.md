# plan.md template

`palpatine-planner` writes `plan.md` from a finished `spec.md`, plus `plan-backend.md` and `plan-frontend.md` holding each builder's units. Write it by hand only when you are taking the planner's place (lane `plan` skips research, not planning).

`plan.md` stays **blank** until it is a plan: any `#`, `##` or `###` heading outside a ledger block tells openlanes the plan is written, and moves the folder from 📋 Ready for Planning to ⭐️ Planned. The whole plan lands as one pull request; more than eight units means the spec is several plans.

```markdown
# Rate Feed Sync — Plan

**Spec:** `spec.md` in this folder
**Depends on:** plans that must land first, by number, or nothing

## Units

### U1 — Rates table and model

- **Discipline:** back end
- **Owns:** db/migrate/*_create_rates.rb, app/models/rate.rb
- **Must not touch:** app/views/**
- **Depends on:** nothing
- **Done when:** spec/models/rate_spec.rb passes

### U2 — Sync command

- **Discipline:** back end
- **Owns:** lib/acme/rates/sync.rb
- **Must not touch:** app/models/rate.rb (U1)
- **Depends on:** U1
- **Done when:** spec/acme/rates/sync_spec.rb passes

### U3 — Integration check

- **Discipline:** back end
- **Owns:** spec/integration/rates_sync_spec.rb
- **Depends on:** U2
- **Done when:** a real sync, nothing stubbed but the vendor's HTTP, stores rows the model reads back

## Order

U1 → U2 → U3. Units that write the same file are sequential; say which can run in parallel and why.

## Risks

| Risk | What we do about it |
| :--- | :------------------ |
|      |                     |

## Task completed when

- copied from spec.md's `task-completed-when`

## How to verify

- copied from spec.md's `how-to-verify`
```

Notes:

- Every unit appears in exactly one of `plan-backend.md` and `plan-frontend.md`, under its own `##` or `###` heading. `rey-frontend` starts only when `plan-frontend.md` has a unit heading, so a plan with no front end writes one plain line there and no heading.
- `## Task completed when` and `## How to verify` are appended by the harness when missing; a section you wrote is left alone.
- A plan stays one level above the code: signatures, routes and response shapes, not method bodies.
