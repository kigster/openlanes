# Decisions on agent memory and sessions

Decided 2026-10-16 by the owner (kig).

A new round today starts a new session with an empty context, and gets back only what is on disk plus a thin resume record. Agents redo work, and spend time and tokens doing it. These decisions keep what an agent learned from one round to the next.

### M1. A round resumes the previous round's session

- An adapter that can resume (`resumes?`; only claude today) MUST resume: the next round of the same agent, on the same plan state, in the same checkout, runs with `--resume <session id>`.
- It starts a new session when the plan has moved to another state, or when the session cannot be found.
- Every round's session id is kept in that round's entry under `stages` in `state.json`, so a person can resume the agent by hand in an interactive session.
- Autocompact stays at 40% of the model's context (`Adapters::AUTOCOMPACT`, passed as `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`), which already applies to every claude invocation.

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

### M5. Sub-agents, capped per agent

- Every agent gets the `Task` tool, with a maximum number of sub-agents at once in its front-matter. The default is 1; `leah-researcher` gets 2.
- The agent drawer shows the setting as a concurrency dropdown, 1 to 4.
- `openlanes init` asks whether to set concurrency per agent. If yes, it goes through each agent with the same 1–4 choice.

## Open

- How M4 relates to E1 in [decisions-on-limit-extensions.md](decisions-on-limit-extensions.md) (PR #62), where a person answers `X<n>` with one round, 10 minutes or 20 minutes.
- Enforcing M5: Claude Code has no flag that caps concurrent sub-agents. The harness sees each spawn in the stream, so it can tell the agent its limit and react when it is exceeded, but it cannot prevent the spawn.
- Where a concurrency change made in the drawer is kept. The proposal is the project's `.openlanes.yml`, per agent, because `agents/*.md` ships with the gem.
