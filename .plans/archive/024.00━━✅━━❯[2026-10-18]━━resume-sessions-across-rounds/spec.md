# 024.00 Resume Sessions Across Rounds

> [!NOTE]
> **Written retroactively on 2026-10-18.** This documents work that shipped in
> #76 (still open at the time of writing; M1 itself is on `main` in `95597c2`).
> It describes what exists; it does not record a decision taken in advance.

## Problem

An agent that gets a second round on the same plan starts from nothing: it re-reads the spec and re-derives context the previous round already paid for. `claude -p --resume <id>` carries a conversation on, so the engine only has to remember the id and decide when reusing it is honest.

### Framings

1. **Engine remembers, adapter resumes.** Store each round's session id in `state.json`; the dispatcher asks `PlanState` whether to resume; the executor passes `--resume`.
1. **Agent remembers.** Let the agent write its own resume notes and always start fresh (the existing `state resume` records, plan 003).

Chosen: 1. It costs no prompt tokens and the decision is auditable from `state.json`; framing 2 stays as the fallback and is unchanged.

## Research

(No `## Research` chapter exists: this plan was written after the fact. Facts below are anchored to code.)

## Goal

Round 2 of the same agent, on the same state, in the same checkout, continues round 1's conversation. Anything else (plan moved, session gone, adapter cannot resume) starts fresh and the log says why. This plan proves that end to end and documents resuming by hand.

## Non-Goals

- Resuming across different agents, or across a plan that changed state.
- Resuming for `codex` or `pi`, which cannot (`Adapters::Claude#resumes?`, `lib/openlanes/adapters/claude.rb:112`).
- Recovering a lost session's context; the agent starts fresh.
- Changing the compaction flow, which also resumes (`executor.rb:847`).
- Any HTTP surface or UI.

## In scope

- [x] Each round's `stages` entry in `state.json` holds `session` and `cwd` (`PlanState#stage!`, `plan_state.rb:221`; `Dispatcher#record_session`, `dispatcher.rb:2019`). Check: integration spec reads `stages`.
- [x] Round 2 argv contains `--resume sess-1`; round 1 has none. Check: `spec/integration/resume_across_rounds_spec.rb`.
- [x] Lost session (`SESSION_MISSING`, `executor.rb:419`) relaunches fresh, argv without `--resume`, log says `session sess-1 not found, starting … fresh`.
- [x] Plan moved: no `--resume`; log says `fresh session: the plan moved to …`.
- [x] Adapter that cannot resume: no flag; log says `fresh session: codex cannot resume one`.
- [x] `docs/USAGE.md:168` "Resuming an agent's session" shows `state show … | jq '.stages[-1] | {session, cwd}'` and `cd <cwd> && claude --resume <session>`, with the rules. Check: read the passage.
- [x] `docs/decisions/decisions-on-agent-memory-and-sessions.md` marks M1 implemented.

## Out of scope

- Changes under `lib/`: the integration spec passed first run, so B2 was a no-op (plan.md build notes).
- Redis-gated paths: 9 pending examples skip without Redis, unrelated.

## Back end / front end

- Back end (`backend-coder`): all items above, including the docs.
- Front end (`frontend-coder`): none.

## Open questions

- PR #76 was still open when this was written; its merge status is assumed, not verified.
- `verifier` was interrupted ("harness died") in round 1, so verification output in `pull-requests.md` is backend-coder's, not an independent run.
- The folder is numbered `024.00` (MM = 0) yet sits in the Retroactive state; the retroactive note follows the state, not the number.
- The build notes' test counts (3550 examples) were not re-run here.

## Risks to planning or execution

- Fake `claude` scripts reach `Child` only via the executor's `spawn:` seam because Bundler fixes `PATH`; a change there silently breaks the spec's realism.
- The fake reports small usage on failure; a zero-usage failure reads as a lost session and is retried fresh.

## Conclusion

When this ships, `state.json` records session and checkout per round, claude agents resume their own previous round, every fresh start is explained in the log, and a person can resume an agent by hand from `USAGE.md`. One six-example integration spec guards the behaviour.
