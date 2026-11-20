---
created: 2026-11-20
lane: full
depth: medium
frontend: false
depends_on: [none]
implementation_suggestions:
  - "Run the checks on the builder's job thread after the executor returns, as plan 060's `Engine::ReviewGating` did, so a minutes-long suite never holds up the dispatcher's tick"
  - "Reuse `Execution::Checks.commands(checkout)` to pick the commands (`just check-all`, or `bundle exec rspec` and `bundle exec rubocop`), so the gate runs exactly what builders are already told to run"
  - "Plan 060's branch (PR #223, head `75e077a9`) has a `PreReviewGate` and specs worth reading first; its findings F5 and F6 below say what to do differently"
implementation_requirements:
  - "A plan whose checks are red after a build round starts no reviewer, staff-reviewer included, and opens or updates no pull request for that round"
  - "On a red gate the plan goes back to the builder or builders whose work it is, each mailed the failing command and the last 40 lines of its output"
  - "For a plan built by a pair (back end and front end), the gate runs once, after the last builder of the round finishes, never once per builder"
  - "The bounce cap counts consecutive red gates and resets when a gate passes; at the cap the plan is blocked with blocked.md naming the command that stayed red, rather than looping"
  - "`review.gate: false` in `.openlanes/config.yml` turns the gate off; it is on by default"
  - "The test suite never runs a real project suite from inside itself: the gate is stubbed green in `spec_helper.rb`, and only examples tagged for it run the real command"
task-completed-when:
  - "A builder that signs Completed on a red suite gets its plan back with the failing output, and no reviewer starts"
  - "A paired plan with a red back end bounces to the back-end builder, not to whichever builder finished last"
  - "Two red gates, then a green one, then a red one in one run does not hit the cap"
  - "`review.gate: false` publishes and starts reviewers as today"
how-to-verify:
  - "RUBYOPT= just ci"
  - "bundle exec rspec spec/openlanes/engine/dispatcher_pre_review_gate_spec.rb"
---

# Gate Review Behind Green Checks

## What we are trying to achieve

No reviewer reads a build whose own tests or linters are red. When a builder signs Completed, the harness runs the project's checks in that plan's checkout first. Red sends the plan back to the builder with the output; green lets the review round start as it does today.

## Why it matters

Today only the stage-2 reviewers wait for green CI (`Engine::Reviews#due?`, through `@build.green?`). staff-reviewer starts unchecked, so a red build costs a full review round, and a finding that only says "the suite is red", before anyone fixes it. The check that builders are asked to run is a request in their prompt; this makes it a guarantee, the same way `Execution::Boundary` turns "do not push" into a check.

This was item 2 of plan 060 (archived; see its `landed.md`). It was built on PR #223, which closed unmerged when the arbitrator ruled no_go at the rejection cap over two findings this plan must not repeat:

- **F5:** the gate ran on every builder's thread and was judged on whichever builder of a pair finished last. That builder was mailed and rerun, the plan held at 🎨, which the back-end builder does not handle, and the plan looped red without the back end ever being told.
- **F6:** the bounce count never reset on a green gate, so it capped red gates in total rather than in a row.

## What needs to be done

1. Decide where the gate sits in the round: after the last builder of the round, before `Rename` publishes and before any reviewer is due. Research should confirm the hook point in `engine/dispatcher/` (`start.rb`, `settle.rb`, `rename.rb`) on today's `main`, which has changed since plan 060.
2. Run the checks in the plan's checkout without blocking the tick, with a timeout (a command past it counts as red), keeping the last 40 lines of output.
3. On red: route the plan back to the builder or builders that own the failing work, mail each the command and the output tail, publish nothing, start no reviewer.
4. Count consecutive red gates per plan, reset on green, and block the plan with blocked.md at the cap.
5. Add `review.gate` (default true) and `review.gate_timeout` to the config, validated, written back only when they differ from the default.
6. Specs at the dispatcher level for: a lone builder red then green; a pair with a red back end; the cap and its reset; the gate turned off.

## Open questions

- Should a red gate count against the plan's attempts, or only against the gate's own cap? Plan 060 counted it as an interrupted round. Research should weigh both and pick.
- Which builder owns a red suite in a pair when both changed files? Probably both are mailed; research should settle it.
