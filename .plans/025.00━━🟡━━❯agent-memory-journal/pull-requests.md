# Pull Requests

## 025.00 Agent Memory Journal — luke-backend, round 1

No frontend half (`plan.md` has no `## Frontend` units), so luke owns the whole plan.

What landed:

- `lib/openlanes/plans/journal.rb`: `Plans::Journal` — `KINDS`, `Entry`, `scan` (one-line JSON entries on lines of their own; an `override` must name `overrides: <n>`), `render` for the prompt.
- `PlanState#journal!` / `#journal`: appends under `memory.<agent>.rounds.<n>`, under the existing lock, numbered per agent across rounds.
- `schemas/plan-state.schema.json`: `memory` and `$defs/journalEntry` (override requires `overrides`; `answer` reserved for M3).
- `Transcript#journal` (claude, top-level assistant text only) and `Adapters::Stream#journal` (codex/pi, deltas skipped); `Executor::Sessions#journal` and `Handle#journal` across compactions.
- `Dispatcher#record_journal`: on every poll and first thing in `settle`, writes only entries not yet written, so a killed agent keeps what it printed.
- `Prompt#journal_section`: every agent (builders and reviewers alike) is told how to journal; round n+1 gets round n's journal, resumed session or not.

Baseline: 3550 examples, 0 failures, 9 pending before; no `contract.md` (no rey).

Checks:

    $ bundle exec rspec
    3572 examples, 0 failures, 9 pending
    $ bundle exec rubocop
    488 files inspected, no offenses detected

Not done (out of scope for M2 as written, flagged for review): recording a `question`'s answer when it arrives (M3; the schema field exists), and a dispatcher-level spec of `record_journal` (covered through `Handle#journal` and `PlanState#journal!`).
