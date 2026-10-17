# Decisions on agent memory and sessions

Decided 2026-10-16 by the owner (kig).

A new round today starts a new session with an empty context, and gets back only what is on disk plus a thin resume record. Agents redo work, and spend time and tokens doing it. These decisions keep what an agent learned from one round to the next.

### M0. The principle: a person intervenes as rarely as possible

This is the primary guiding principle of the whole system, and every decision here is measured against it. An agent is asked before a person (M4); nobody answering has a default; and the questions a person must answer are asked up front, while they are already there, rather than as blocks in the middle of a run.

### M6. A new idea is grilled before its spec is saved

When a person adds a new idea through the page, the page interviews them, one question at a time with a recommended answer each, as the grill-me skill does, before `spec.md` is written. The answers go into the spec, so the agents downstream find the decisions already made instead of blocking to ask for them.

### M1. A round resumes the previous round's session

- An adapter that can resume (`resumes?`; only claude today) MUST resume: the next round of the same agent, on the same plan state, in the same checkout, runs with `--resume <session id>`.
- It starts a new session when the plan has moved to another state, or when the session cannot be found.
- Every round's session id is kept in that round's entry under `stages` in `state.json`, so a person can resume the agent by hand in an interactive session.
- Autocompact stays at 40% of the model's context (`Adapters::AUTOCOMPACT`, passed as `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`), which already applies to every claude invocation.

Implemented (plan 024). `Plans::PlanState#resumption` decides from `state.json` whether a round resumes and why not; `Engine::Dispatcher#resumption_for` asks it, logs the decision and hands the session to the executor, which starts fresh when the CLI cannot find it. `spec/integration/resume_across_rounds_spec.rb` drives all of it through a real `Runner` and a fake `claude`. Resuming by hand is in `docs/USAGE.md`, under "Resuming an agent's session".

### M2. The agent keeps a journal, which the dispatcher writes

- The agent writes nothing to a file and runs no command. It prints each entry as one line of JSON in its own output, and the dispatcher, which already reads every agent's stream, appends it to `state.json` under `memory.<agent>.rounds.<n>`. The harness is the only writer, under the lock `PlanState` already takes, so a pair working at once cannot collide.
- An entry is `{ "kind", "text" }` and, for an override, the number of the entry it overturns. There is no timestamp: the list is ordered, and a later entry wins over an earlier one.
- Kinds: `todo`, `done`, `decision`, `question`, `override`, `note`.
  - `question`: the agent stopped to ask. Its answer is recorded with it, by the dispatcher, when the answer arrives.
  - `override`: a decision that contradicts an earlier one, whether it came from an answer or from the agent itself.
  - `note`: anything else the agent must not forget.
- The agent is told to record each of these as it happens, not at the end, so a round that is killed still leaves everything it printed.
- Reading the previous round is enforced, not requested: the dispatcher puts the previous round's journal into the next round's prompt, even when the session is resumed. Agents that cannot resume depend on it, and claude benefits too.
- This replaces asking a stopped agent to save its work (STOP needs no new instruction).

### M3. More than one block, answered one at a time

Amends the earlier practice of a single question per `blocked.md`.

- An agent may write several questions (`## B1`, `## B2`, …) when there truly are several issues.
- A person sees them one at a time, answers them one at a time, and each is drained from `blocked.md` on its own. When the last one is gone, the plan is unblocked and continues.
- Every question and its answer go into the asking agent's journal (M2) with their numbers, B1 with A1 and so on.

### M4. The agent can ask for more time

- Before its clock runs out, the dispatcher asks the running agent whether it needs more time, and the agent may say yes.
- Time is added in chunks of 5 minutes, a setting in the gem's global configuration.
- After 30 minutes added in total, the agent is interrupted and a new round starts, resuming its session (M1), with autocompact at 40%.
- The agent is asked first; a person only after it. The `X<n>` card of E1 in [decisions-on-limit-extensions.md](decisions-on-limit-extensions.md) goes to a person only when the 30 minutes are used up, or when the agent is out of rounds. E1's automatic 10 minutes is replaced by the agent's own chunks.

### M5. Sub-agents, capped per agent

- Every agent gets the `Task` tool, with a maximum number of sub-agents at once in its front-matter. The default is 1; `leah-researcher` gets 2.
- The agent drawer shows the setting as a concurrency dropdown, 1 to 4.
- A change made in the drawer or by `openlanes init` is saved per agent in the project's `.openlanes.yml` (`agents: { luke-backend: { concurrency: 2 } }`). `agents/*.md` ships with the gem and keeps the defaults; the project file overrides them.
- `openlanes init` asks whether to set concurrency per agent. If yes, it goes through each agent with the same 1–4 choice.
- The prompt states the limit. Claude Code cannot be told to cap sub-agents, so the harness counts the running ones in the agent's stream; an agent that goes over it is stopped as on a timeout: STOP, the kill after the grace period, and a new round, which resumes the session (M1) and reads the journal (M2).
