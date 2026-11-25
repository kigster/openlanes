# Decisions on limit extensions

Decided 2026-10-16 by the owner (kig).

An agent that runs out of time or rounds used to stop: the clock said STOP and then killed it, and an agent with no rounds left was never dispatched again. Now it asks for more first. This builds on D7 in [decisions-on-blocks-and-escalation.md](decisions-on-blocks-and-escalation.md), which gave a person a **Give another round** button after the fact. Here the harness asks before the agent stops, and a nobody-answers default keeps a headless run moving.

### E1. The harness asks, on the agent's car, with three fixed choices

- **Who asks.** The harness, not the agent. The request is `X<n>` in the plan's `state.json` under `extensions`, so it survives a restart and any control room can answer it. The plan keeps its state; nothing is renamed.
- **What it offers.** Always the same three choices: a) Extend Rounds by 1, b) Extend Time by 10 minutes, c) Extend Time by 20 minutes. There is no text box and no Hold button, since nothing is blocked.
- **Time** is asked while the agent still runs, 5 minutes before its clock's zero, the same moment the agent is told "5 minutes left". If the answer is a time choice and that agent is still running, it moves the live deadline and the agent carries on in the same session. If nobody answers, STOP and the kill happen as before. A time choice that arrives after STOP, or a choice on a rounds request, grants one more round with the extra time on its clock. Whenever a round ends, however it ends, its open time request is closed.
- **Rounds** are asked once the agent has used every round it had on the plan's state without finishing (its last status is neither Completed nor Blocked). Every choice grants one more round, and b) and c) also add 10 or 20 minutes to that round's clock.
- **Nobody answering.** Each kind is granted once without an answer, per agent and plan state:
  - Time: 10 more minutes when the clock reaches 120 seconds, before the WRAP_UP at 60 and before STOP. When that time runs low too, the round asks again, and that request waits for a person.
  - Rounds: one more round, at once on a run with no control room (`openlanes run`), or 5 minutes after asking on a run that has one.

  After that the request waits for a person, and the limit applies as it always did. An answer from a person adds to the automatic grant; it does not replace it.
- **Closing.** A round that ends well closes its open request, so the page stops asking.

The once-per-(agent, state) scope for the automatic grant and the "a person's answer adds on top" rule were the implementer's reading of "auto-extend once", recorded here so they can be revisited.

# Time without a person

Decided 2026-11-15 by the owner (kig). E2 changes the time half of E1; the rounds half stands as written.

### E2. A clock that runs low climbs a ladder before it reaches a person

The backend coder kept running out of time a few minutes short, and under E1 each of those waited on a person: one automatic 10 minutes per agent and state, then a card. Now the engine works the extension out while the agent keeps working, and nothing on the ladder stops or kills an agent because a decision is still out.

1. **The engine adds time on its own**, up to `extension_cap` per agent per round (900 seconds unless the agent says otherwise), as soon as the clock reaches 5 minutes. It is one grant of the whole cap, not several small ones: the clock only limits, so an agent that finishes early gives the rest back by ending, and each smaller step would have told it "5 minutes left" again and had it wrap up again.
1. **The agent is asked**, once a round, when that time runs low too. The question is a line in its control file (`ESTIMATE: ...`), and the answer is `openlanes state estimate --plan NNN --agent NAME --minutes N --why "..."`. That is a `state` subcommand because `openlanes state` is the one command every agent is already granted, the confined ones included, so the autonomy boundary is unchanged. The protocol is taught once, in the control-file section of every prompt (`Execution::Prompt`).
1. **An estimate within `extension_cap` is granted as asked**, on the running clock. One threshold, not two: what the engine would add unasked it also grants on the agent's word.
1. **A larger estimate goes to the arbitrator** before any person, as a side call (`Engine::Arbitration::Overtime`): off the loop's thread, the answer applied on a later tick, an unreadable one backed off and given up on after three, by the same `Retries` the rulings use. It answers with an `extension` block, `decision: grant` with `minutes:`, or `decision: decline`. The engine cuts a grant to `extension_ceiling` (3600 seconds unless the agent says otherwise) rather than trusting the number.
1. **Only then a person.** No estimate within 5 minutes, no ruling within 10, a decline, or an arbitrator given up on (or a run that has none): the request becomes the `X<n>` card of E1, unchanged, and the old limit applies, STOP at zero. Later shortfalls in the same round are a person's from the start.

**Holding the clock.** While steps 2 to 4 are out the clock is held near 180 seconds (raised back to it whenever it has fallen 30 below), above the WRAP_UP at 60, silently, so the question stays the line in the agent's file. The hold is bounded by the two deadlines, counted on the wall clock from times in `state.json`: a decision that never arrives holds a clock for 15 minutes at most, restarts included, and then ends at step 5.

**State.** Every step is a request under `extensions` in the plan's `state.json` before it is a move of the clock. A request the engine is still working out carries `stage: estimate` or `stage: arbitration` and shows no card; `stage: person`, or no stage, is a person's. `by:` says who granted: `auto`, `estimate`, `arbitrator`, or a person's name. A restarted engine reads the cap already spent and the stage a request reached, so it grants nothing twice and asks nobody twice; an arbitrator that was mid-answer is asked again inside the same deadline.

**One machine's settings.** `.openlanes/config.yml` `agents:` overrides, per agent, `timeout`, `rounds`, `model`, `effort`, `extension_cap` and `extension_ceiling`. The definition in `agents/<name>.md` stays the source of every default, and an agent the file leaves out runs as its definition says. `Agents::Registry` lays the overrides over each definition as it loads, so the round count, the clock, `openlanes agents list` (marked `*`) and `agents describe` all show the value in force. For `model` and `effort` the override stands exactly where the frontmatter stood in `Agents::Profile`'s order: `run --model`, the plan's spec.md `phases:`, `sizing:` and `depth` still outrank it, because a plan's own spec is more specific than a machine's file. `rounds` is held to 1 to 5, like the frontmatter's, `--rounds` replaces every agent's number (still 1 to 5), and `--timeout` still only tightens.

A run built to ask and never grant (`Extensions.new(auto: false)`) skips the ladder and raises the person's card at once.
