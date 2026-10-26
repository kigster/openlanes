# Filing Deadlines

Show each small business its next estimated-tax filing deadline, moved for weekends and holidays.

## What research needs to settle

1. Which deadlines apply, and where do they come from?
2. How is a deadline moved when it falls on a weekend or holiday?
3. Does the codebase already know about holidays?

## Research

Four quarterly deadlines apply (https://tax.example.gov/estimated-payments). Weekend dates move to Monday. `lib/calendar.rb` has a holiday list.

### Contradictions

None found.

### Could not settle

Nothing.

> [!NOTE]
>
> [2026-09-04 11:29:20 AM PDT] [ agent: researcher   status: Started, round 1 ]
> [2026-09-04 11:30:12 AM PDT] [ agent: researcher   status: Completed, round 1 ]
