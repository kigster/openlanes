# Decisions on memory compounding, and the gaps left by plans 060 to 064

Decided 2026-11-19 and 2026-11-20 by the owner (kig), in three rounds of questions.

Agents should get better with every plan, in this project and across every project on the machine. The memory code in `lib/openlanes/memory/` already curates candidates after a run, but nothing promotes them, nothing writes the global store, and no agent outside an openlanes run can read or teach it. On 2026-11-19 the inbox held three candidates, each from one plan, and `.openlanes/memory/lessons/` held none.

The same session audited plans 060 to 064 against `main`. Most of their work had landed; the gaps found are decided here too.

This work is done by one person's session with its own sub-agents, not by the openlanes factory.

## Memory

### C1. The engine opens the memory pull request

At the end of a run, when any candidate in `.openlanes/memory/inbox/` is eligible, the engine runs the promotion that `ol memory promote` runs today and opens the "Memory: N lessons" pull request. A person still merges it. Agents commit candidates freely; only a candidate becoming an active lesson needs review.

### C2. A candidate is eligible after two plans, and the curator is helped to see repeats

`Promotion::THRESHOLD` stays at 2 distinct plans, or a manual `ol memory approve`. Today a repeat counts only when the curator happens to reuse the exact slug, so one-plan candidates wait forever. The curator's prompt now carries the slugs and titles of every candidate in the inbox and every active lesson, and it is told to reuse a slug when its lesson says the same thing.

### C3. A lesson becomes global automatically, once two projects hold it

- Every lesson promoted in a project is mirrored into the per-user store, `${XDG_CONFIG_HOME:-~/.config}/openlanes/memory/` (or `$OPENLANES_MEMORY_HOME`), as a candidate tagged with the project it came from.
- When two different projects hold the same lesson, it turns active in the global store. No review: the store is local to the user and never committed.
- The read path already merges global lessons after project ones; a project lesson with the same id wins.

### C4. Agents outside an openlanes run can read and teach

- `ol memory list --phase <phase>` prints the lessons section an agent in that phase would get, without naming an openlanes agent.
- `ol memory propose` files a candidate from the command line through the same checks the curator's output passes (`Memory::Secrets`, instruction-like text, `Lesson.parse`).
- Lessons stay addressed by role and phase, not by file path.

### C5. A lesson is measured by citation

- An agent names the lessons it applied (`L-0007`) in its report. The engine records each citation as an event; there is still no `usage.json`.
- `ol memory report` shows, per lesson, how often it was offered and how often it was cited.
- A lesson offered in 15 plans and cited in none is proposed for retirement in the next memory pull request. Graduation (a lesson becoming a check, a rule or an eval case) stays a person's call.

## Gaps left by plans 060 to 064

### C6. The ghost folders for 061 to 064 are traced before they are removed

The folders `061.00` to `064.00` in `.plans/` hold only `state.json` (062 also `blocked.md`), reappeared on 2026-11-15 after the plans were archived, and the engine has spent researcher and unblocker runs on them. What recreated them is found and fixed first; the folders are removed in the same pull request.

### C7. Plan 060 moves to the archive as Done

It was discarded on 2026-11-14 because its pull request #223 closed unmerged, yet four of its five items landed through other pull requests. It moves to `.plans/archive/` as Done, with a note listing which items landed in which commits, and that the review gate moved to its own plan (C8).

### C8. The review gate gets its own plan

Today only the stage-2 reviewers wait for green CI (`engine/reviews.rb`); the staff reviewer starts unchecked and a red suite does not bounce to the builder. This is written as a normal plan folder for the factory to build later, not built in this session.

### C9. The remaining per-PR `gh` reads move to the shared snapshot

`engine/merging.rb`, `upkeep/sweep.rb` and `engine/arbitration.rb` still read pull requests one at a time. They read from the batched snapshot plan 061 introduced, as its contract already admitted they should.

### C10. This repository caps each plan at $25

`plan_usd: 25` is set in `.openlanes/config.yml`. When a plan reaches it, the engine refuses another round on that plan.

### C11. A cap that cannot be enforced refuses to start the run

When a cap is set and the event log is off, the cap cannot be counted. The run refuses to start and says why, until events are enabled or the cap is removed. The terminal board also shows each plan's spend, which today only the web page shows.

### C12. Builder sizes, and the Fable 5.2 price

- `sizing:` in this repository's config: small units on sonnet at medium effort, medium on opus at medium, large on opus at high.
- `claude-fable-5-2` is added to the price list from the official prices, looked up rather than guessed. It is used only when a spec asks for it.

### C13. A rate limit pauses new starts on that adapter

When one agent hits a rate limit, agents already running carry on, and no new agent starts on the limited adapter until its wait ends. Other adapters are unaffected, and the board says which adapter is paused and until when.

### C14. The keyboard test is proven or fixed

`web/cypress/e2e/keyboard.cy.ts` passes in repeated runs, or the cause of the failure the plan's own check saw is found and fixed.

## How the work is done

- One pull request per item, each in its own worktree, seeded with `setup-worktree`.
- At most three sub-agents at once. Every sub-agent reads the lessons for its phase before it starts, and files candidates through `ol memory propose` once that exists.
- The author merges their own pull request once it is green and every review comment is answered.
- Order:
  1. This file.
  2. C6, the ghost folders.
  3. Memory, one at a time because the items share `lib/openlanes/memory/`: C4, C1, C2, C3, C5.
  4. Beside the memory work, where the files do not overlap: C7, C9, C10 with C11, C12, C13, C14, and the plan folder for C8.
- The branch `kig/034.00-refactor-global-lock` (`fc1ccda4`, local only, a salvaged draft from 2026-10-23) is compared with `main` and reported on. Nothing is deleted.
