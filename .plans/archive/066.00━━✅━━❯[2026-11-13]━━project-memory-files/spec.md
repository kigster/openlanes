---
created: 2026-11-12
starts: planning
depth: deep
frontend: false
depends_on: [none]
implementation_suggestions:
  - "Follow `docs/continuous-learning.md`, sections 'Where lessons come from' and 'The curator, and why agents never write memory directly'"
  - "Add the curator as `agents/curator.md`, and the promotion step as plain Ruby under `lib/openlanes/memory/`, beside `Library` and `Lesson`"
  - "Open the memory pull request through `Vcs::Publisher`, as a build's is"
implementation_requirements:
  - "Build on `OpenLanes::Memory` from pull request 196; do not add a second lesson format or a second reader"
  - "No agent writes into `.openlanes/memory/lessons/` directly: the curator writes candidates into `.openlanes/memory/inbox/`, and only the harness promotes one"
  - "Every change to `lessons/` reaches `main` as its own pull request, which a person merges; `gh pr merge` stays ungrantable"
  - "A candidate's text is treated as untrusted: single plain lines for id, title and names, and no instructions aimed at other agents"
  - "Nothing sensitive ever reaches `.openlanes/`: no API key, token, password, private key, connection string with credentials, credential value from `.env` or Rails credentials, or person's email address. The harness, not the curator's prompt, enforces it: a deterministic scan runs before a candidate is written to the inbox and again before promotion, and a match drops the candidate and reports it without printing the matched value"
  - "The same scan runs over the whole `.openlanes/` folder in the suite and in CI, so a secret added by hand fails the build"
  - "The entire `.openlanes/` folder is committed with the project: nothing under it is gitignored, and nothing a running process owns (locks, PIDs, caches, traces, usage counters that churn every run) is stored there"
  - "Every agent has memory addressed to it by name, and it accumulates: a lesson stays until it is superseded or retired by a reviewed change, each confirmation of it in a later plan is counted, and what an agent is shown is ranked so confirmed lessons outlast one-off ones"
  - "A run started with `--no-memory` writes no candidate and promotes nothing"
task-completed-when:
  - "A plan that ends rejected, rewritten or merged leaves candidates in the inbox, each naming its evidence"
  - "A candidate seen in two plans, or approved by a person, becomes an active lesson in a memory pull request"
  - "After that pull request merges, the next run's agents are shown the lesson by `openlanes memory list --agent NAME`"
  - "Lessons are addressed to an agent name or a phase and to everyone, so each agent has its own memory and the project has a shared one"
  - "An agent on its tenth plan is shown what it and its predecessors learned on the first nine, within the prompt budget"
  - "`git status --ignored .openlanes` reports nothing ignored, and a planted fake API key in a candidate never appears in any file under `.openlanes/`"
  - "The events report compares rounds to approval with memory on and with `--no-memory`, so compounding can be measured"
---
# Project Memory: the Writer

Source: the owner, 2026-11-12. "Agents in a single repo maintain a per-agent and a global memory file which would allow the agents to compound the knowledge about the project, and what they have done so far. The hope is that the agents will use that information to get smarter over time." Stored with the repository, in `.openlanes/`.

## What we are trying to achieve

Phase 2 of `docs/continuous-learning.md`: the part that writes. Pull request 196 (merged) built the read side: every agent's prompt already carries the active lessons for its name or phase, read from `.openlanes/memory/lessons/` on the default branch. Nothing writes a lesson yet, so the folder is empty and agents learn nothing from one plan to the next.

This plan adds the curator agent, the inbox of candidate lessons, the deterministic promotion step, and the memory pull request.

## Why it matters

The same lessons are paid for on every plan. On 2026-11-12 alone: two Redis outage specs flap and each new agent investigates them from scratch; six specs fail on a clean `main` and every builder rediscovers that; an unblocker went in a circle over a file that exists in a worktree and not in the main checkout. Each is one lesson.

## What already exists

- `OpenLanes::Memory` (`Lesson`, `Library`, `Section`, `Committed`, `Folder`), `openlanes memory list`, and `run --no-memory`, from pull request 196.
- The design, including why memory is one shared store addressed by role and not one file per agent, and why agents never write it directly: `docs/continuous-learning.md`.
- The signals the curator reads are already recorded: reviewer verdicts and findings in `state.json`, `rewrite.md`, arbitration rulings, answered questions drained from `blocked.md`, verifier failures.
- The per-plan journal (`Plans::Journal`, decision M2) is a different thing: one agent's notes within one plan.
- Plan 025.00, "agent memory journal", sits in `.plans/discarded/`. It covered that per-plan journal, which reached `main` another way, so this plan replaces it under a new number and does not revive its `plan.md`.

## Open, for the planner to settle or ask

These are the design document's own open questions. The location is settled by pull request 196 and by the owner: `.openlanes/memory/`.

1. Promotion: two plans, or always a person until the curator has earned trust.
2. Whether a memory pull request is bundled with the plan's pull request or always separate.
3. Where `usage.json`, the count of how often a lesson is cited, lives. It changes on every run, so it cannot sit in `.openlanes/` under the rule that everything there is committed and nothing churns; the XDG state directory is the likely home.

## Out of scope

Global memory across projects (phase 3), graduation of lessons into evals and docs (phase 4), and moving `.openlanes.yml` (plan 067.00).

## How to tell it's working?

- bundle exec rspec
- bundle exec rubocop
- An integration spec takes two plans with the same rejected finding through the curator in a temp repository and finds one active lesson in the proposed pull request
