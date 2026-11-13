---
created: 2026-11-10
starts: planning
---

# Improve Openlanes Low Hanging Fruit

## What we are trying to achieve

Improve overall codebase quality and speed of software factory.

## Why it matters

The factory often gets stuck and the agents take forever.



## What needs to be done

1. Give reviewers one prepared packet. All three reviewers each re-read spec.md, plan.md, contract.md and pull-requests.md and run gh pr diff themselves. Have the harness build the diff and a spec digest once and inject it. This cuts three sets of tool round-trips and makes the 300 s timeout safer.

2. Gate review behind lint and tests. There is no deterministic check between build and review; the coverage gate appears to run at verification. **A red suite should bounce to the builder before any reviewer is started.**

3. Size the builder by the work unit. backend-coder runs opus/high for every plan. **Let the planner tag each unit small, medium or large, and have Profile map that to model and effort.** Add an option to .openlanes.yml that allows Fable 5.2 to be used on the most complex features.

4. Handle provider rate limits explicitly. **There is no rate-limit or overloaded handling in executor.rb.** With jobs: 7, a HTTP 429 should pause and requeue with backoff, not count as a failed attempt (check first).

5. Split dispatcher.rb. At 141 methods it is the main reliability risk; each tick step (assign, poll, settle, rename) should be its own object, as steps/ already started. This refactor is critical to the success of the factory.

   
