# Blocked: 009.00 plan-aging-and-bombs

Asked by luke-backend, 2026-10-13. Technical.

## B1 Plan 008 (the dependents index) is not merged yet. How should 009 proceed?

The aging sweep (unit B3) bombs only blocked plans that other plans depend on, and defers the ones nobody depends on. Nothing in `lib/` reads `depends_on` until plan 008 merges; 008 is built (🟢) and its pull request #23 is open. Units B3 to B7 sit behind it (`plan.md`, Prerequisite). B1 (the 💣 state) and B2 (`plans.aging_since`) are built and green.

a) **Recommended.** Wait for #23 to merge, then resume 009 at B3.
b) Build a small private `depends_on` reader inside `lifecycle/aging.rb` now, to be replaced by 008's index later. It writes the dependents fact down twice, which `CLAUDE.md` warns against.
c) Ship B1 and B2 alone in this pull request, and split B3 to B7 into a follow-up plan that depends on 008.
d) Type something instead
