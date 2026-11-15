---
created: 2026-11-10
starts: planning
<<<<<<< HEAD:.plans/060.00━━🔴━━❯improve-openlanes-low-hanging-fruit/spec.md
depends_on: [none]
||||||| parent of 93b20aa6 (UPDATE THE PLANS):.plans/060.00━━⚪━━❯improve-openlanes-low-hanging-fruit/spec.md
=======
task-completed-when:
  - "Every reviewer's prompt carries the pull request's diff and the plan documents, built once per review round by the harness"
  - "A plan whose checks fail after the build goes back to its builder, and no reviewer is started for it"
  - "The planner sizes each work unit small, medium or large, and the builder's model and effort follow the size"
  - "A provider rate limit or overload pauses the agent and retries with backoff, and is not counted as a failed attempt"
  - "`lib/openlanes/engine/dispatcher.rb` is under 400 lines, with assign, poll, settle and rename each in an object of its own, and no behaviour changed"
>>>>>>> 93b20aa6 (UPDATE THE PLANS):.plans/060.00━━⚪━━❯improve-openlanes-low-hanging-fruit/spec.md
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

## What already exists

Checked against `main` on 2026-11-10.

1. **Review packet.** `agents/staff-reviewer.md`, `security-reviewer.md` and `design-reviewer.md` each tell the reviewer to read `spec.md`, `plan.md`, `contract.md`, `pull-requests.md` and to run `gh pr diff <n>`. `agents/shared/review.md` is the brief all three share, appended by `Execution::Prompt#review_brief`. `Engine::Reviews` owns a review round. Each reviewer has `timeout: 300`.
2. **Gate.** `Execution::Checks` derives the project's commands (`just check-all`, else `bundle exec rspec` and `bundle exec rubocop`) and `Prompt#requirements_section` only *tells* agents to run them. Nothing in the engine runs them. `Checks::PHASES` includes `review`, so each reviewer is also told to run the whole suite, which takes about 7 minutes here against a 300 s timeout. `Engine::CoverageGate` is the pattern for a harness-run command with a timeout.
3. **Sizing.** `Agents::Profile` already resolves adapter, model and effort with a documented precedence (spec `phases.<phase>`, then `depth`, then the agent's frontmatter). `agents/planner.md` splits a spec into work units but gives them no size. `Adapters::Claude::CEILING` is hard-coded to `"opus"`, so a Claude agent asked for Fable runs on Opus, and `CATALOGUE` lists `claude-fable-5-1`, not 5.2.
4. **Rate limits.** `Executor#lost_session` restarts once, immediately, any invocation that failed having spent nothing; its comment says that also catches "an overload, an auth error or a network drop at start-up, which the fresh start will usually hit again". There is no backoff, and a rate limit met mid-run is treated like any other failure. `Live::Outage` and `redis_backoff` are the existing pause-and-resume pattern, for Redis.
5. **Dispatcher.** `lib/openlanes/engine/dispatcher.rb` is 2,523 lines and 141 methods. `engine/steps/` (`Merges`, `Sweeps`, `Watch`, `Interval`) and `Engine::Upkeep` are the pattern for a step pulled out of it.

## Notes for whoever builds this

- Item 2 makes the reviewers' own suite run redundant: once the harness gates on the checks, take `review` out of `Checks::PHASES` and say in the packet that the checks passed, with the commit they passed on.
- Item 1's packet is stable text, so put it ahead of anything that changes per round to keep it in the prompt cache. A large diff needs a size cap, with the reviewer told to fetch the rest itself.
- Item 3 needs a new `.openlanes.yml` key for the ceiling. Plan 057.00 adds a JSON Schema for that file; whichever lands second adds the key to the schema.
- Item 5 overlaps plan 045.00 (SOLID sweep), which names the dispatcher as its first seam and adds dry-system. Here it is a plain extraction with behaviour frozen: no spec assertion changes, only new specs for the new objects. 045.00 then starts from the smaller file.
- Item 5 is not low-hanging fruit and every other item in plans 060 to 064 edits the dispatcher, so it goes first and alone.

## Decisions needed

- The rates for Fable 5.2 (dollars per million tokens in and out) for `Adapters::Claude::CATALOGUE`.
- The size-to-model table for item 3. Proposed: small is sonnet/medium, medium is opus/medium, large is opus/high, and large becomes fable/high only when the new ceiling key allows it.

## How to tell it's working?

- bundle exec rspec spec/openlanes/engine spec/openlanes/execution spec/openlanes/agents
- wc -l lib/openlanes/engine/dispatcher.rb
