# Filing Deadlines

Show each small business its next estimated-tax filing deadline, moved for weekends and holidays.

## What research needs to settle

1. Which deadlines apply, and where do they come from?
2. How is a deadline moved when it falls on a weekend or holiday?
3. Does the codebase already know about holidays?

## Research

### Reuse in this repo

- `lib/calendar.rb:3`: `Calendar::HOLIDAYS`, a hard-coded list of three holidays for 2025 only. It answers question 3: the codebase knows some holidays, but nothing for 2026 and nothing about observed dates.

### Existing components

- [holidays](https://github.com/holidays/holidays): holiday definitions by region, including observed-date rules; fits as the source for the weekend and holiday shift.
- [business_time](https://github.com/bokmann/business_time): business-day arithmetic over a holiday list; fits for "the next business day" once the holidays are known.

### Open questions for spec-writer

1. Which deadlines apply, and from which authority: federal only, or state schedules as well?
2. When a deadline falls on a weekend or holiday, which rule moves it, and does an observed holiday count?
3. Should `Calendar::HOLIDAYS` be replaced by a package, or extended by hand each year?

> [!NOTE]
>
> [2026-10-24 11:29:20 AM PDT] [ agent: researcher   status: Started, round 1 ]
> [2026-10-24 11:32:51 AM PDT] [ agent: researcher   status: Completed, round 1 ]
> [2026-10-24 11:32:52 AM PDT] [ next: spec-writer ]
