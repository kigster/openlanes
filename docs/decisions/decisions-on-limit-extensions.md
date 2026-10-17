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
