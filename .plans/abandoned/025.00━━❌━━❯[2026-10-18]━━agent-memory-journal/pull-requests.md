# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 83 | [\[025.00\](A) Agent Memory Journal](https://github.com/kigster/openlanes/pull/83) | Closed 🔴 |

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

## 025.00 — luke-backend, fixes for hansolo's review (rejected 1/2)

1. Override checked against a real entry: `PlanState#journal!` keeps an override whose `overrides` is not below its own number as a `note`, under its number, so the agent's count and the stored one agree. The prompt now says entries are numbered 1, 2, 3… in print order, across rounds, names this round's first number (`PlanState#next_journal_number`), and that only well-formed lines are numbered.
2. Generic stream dedupe: `Stream#note_journal` treats a text that extends the previous one as the same message and takes only the entries past those already taken, so `message_update` then `message_end` yields one entry. Spec: `journal_capture_spec.rb`, "keeps an entry once when a growing message is sent again whole".
3. `spec/openlanes/engine/dispatcher_journal_spec.rb`: two polls, then a killed job settles; `state.json` holds each entry once, in order. Checked by mutation: `entries.drop(done)` → `entries` fails it, and so does removing `record_journal(job)` from `settle`.
- Also: the `questions_section` YARD comment is back above `questions_section`.

Checks:

    $ bundle exec rspec
    3577 examples, 0 failures, 9 pending
    $ bundle exec rubocop
    489 files inspected, no offenses detected
