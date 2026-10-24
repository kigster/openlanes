---
created: 2026-10-23
lane: full
---

# Stuck Agents Ask

Decided with the owner (kig) on 2026-10-23. An agent that fails, restarts from its resume note with the same prompt and model, and fails the same way, today loops until its rounds run out; the drawer then offers only "Give another round", which restarts the same loop. Nobody is asked why. Every item below is wanted.

## Decided

S1. **Same failure twice is a question.** The harness fingerprints each failed round (agent, the state it started from, the error normalised to a class). On the second identical fingerprint it does not restart the agent: it writes a `blocked.md` question in the D3 shape, with the context (what was tried, both errors) and options: a) another round with a hint (text box), b) another model or adapter, c) send the plan back to an earlier state, d) I will fix it by hand.

S2. **Sort failures by who can fix them.** Harness and environment failures (publish refused, boundary violation, a port or CI infrastructure fault, a `next:` naming an agent that does not handle the state) go straight to a person and spend no agent round. Only failures in the agent's own work get rounds.

S3. **A sharper second-round prompt.** A retried round is told how the previous one failed and that, if it sees no different approach, it signs `Blocked --note technical` with a question instead of repeating itself.

S4. **The loop is visible.** The drawer says "attempt 2 of 3, same failure as attempt 1: ...", not only "out of rounds".

S5. **D7 is amended.** "Give another round" becomes one option among S1's, not the only button.

S6. **Micromanage.** A new item in the agent drawer's Action menu (`web/src/panels/AgentActionMenu.tsx`), titled "Micromanage": it interrupts the running agent (the `INTERRUPT` control word, so it leaves a resume note), takes a clarifying message from the person, and restarts the agent from its resume note with that message in its prompt. The interrupted round is handed back, as `Dispatcher#requeue` does, so micromanaging never costs a round.

S7. **The round is on the car.** A running car shows its round (e.g. `R2/3`) beside the rotating gear it already has (`web/src/board/Car.tsx`, `Gear`).

## Amends

`docs/decisions/decisions-on-blocks-and-escalation.md`: D1 (partners settle their own questions) gains the repeat-failure exception, D7 is replaced by S4/S5. Plan 036.00 R6 ("the resolver never blocks") keeps its rule for conflicts, but a second identical rebase failure falls under S1.

## Evidence

Plan 020.01 on 2026-10-21: luke-backend and rey-frontend both completed, then "publish refused"; rey's `next:` named hansolo-reviewer, who does not handle 🔴. Earlier, its suite failed for a reason on the machine (loopback ports), not in the plan.

## What we are trying to achieve

Stop a failing agent from looping silently. When the same failure repeats, the harness asks a person a question (a `blocked.md` entry with options) instead of spending more rounds. Failures that are not the agent's own work (publish refused, boundary violation, CI or port faults, a bad `next:`) go straight to a person. The drawer shows attempt counts and the same-failure reason, and a new "Micromanage" action interrupts a running agent and restarts it with a clarifying message. The round also appears on the car.

## Why it matters

Per the author's note, a repeated failure today runs until rounds are exhausted and the drawer only offers "Give another round", which repeats the same loop. Plan 020.01 (2026-10-21) shows the cost: two agents finished, then "publish refused" was routed to a reviewer that does not handle 🔴, and no one was asked.

## What already exists

- Interrupt and resume: the control file in `lib/openlanes/execution/control.rb` (per `CLAUDE.md`, the layout moved from `lib/agentilda/control.rb`, which is named in archived plan `.plans/archive/003.00━━✅━━❯[2026-10-15]━━inter-agent-communication/spec.md`). That archived spec documents `INTERRUPT` and `openlanes state resume`. Resume sessions across rounds: `.plans/archive/024.00━━✅━━❯[2026-10-18]━━resume-sessions-across-rounds/`.
- Time extensions and interrupts: plan `.plans/027.00━━⭐━━❯agent-asks-for-more-time/spec.md` (decision M4 in `docs/decisions/decisions-on-agent-memory-and-sessions.md`, amending E1 in `docs/decisions/decisions-on-limit-extensions.md`). Code: `lib/openlanes/engine/extensions.rb`.
- Dispatcher loop: `lib/openlanes/engine/dispatcher.rb`, where `requeue` is named in the author's note. Runs and rounds are recorded in `lib/openlanes/engine/state_file.rb` and the journal (`docs/decisions/decisions-on-progress-journal.md`, plan 039.00, archived).
- Questions: `blocked.md` is written by agents and folded back by `lib/openlanes/lifecycle/unblocker.rb` (`openlanes unblock NNN`). The format rules are in `docs/decisions/decisions-on-blocks-and-escalation.md` (D1, D3, D7), which this plan amends.
- Failure sorting: `lib/openlanes/execution/executor.rb` and `lib/openlanes/execution/boundary.rb` produce the "boundary violation" and "publish refused" failures S2 needs to separate.
- Web: `web/src/board/model.ts`, `web/src/api/types.ts` and the fixtures under `web/src/api/fixtures/`. Not checked: `web/src/panels/AgentActionMenu.tsx`, `web/src/board/Car.tsx` and `Gear`. Those names come from the author's note and I did not confirm they exist.
- Per-plan state: `state.json` schema in `schemas/plan-state.schema.json`, read by `lib/openlanes/plans/plan_state.rb`.

## What research needs to settle

- The fingerprint: exactly which fields define "same failure" (agent, starting state, error class). How errors are normalised to a class, and where that mapping lives.
- Which existing failure paths already carry a class that S2 can key on, and which ones need a new one.
- How "Micromanage" interacts with the `INTERRUPT` control word and the 120-minute stale-lock rule, and how the interrupted round is handed back without a cost.
- Whether `Blocked --note technical` is already a valid signature in `state.json`, and what the `blocked.md` D3 shape requires.
- Whether the amendments to D1 and D7 conflict with plan 036.00 R6, which the author says keeps its conflict rule.

