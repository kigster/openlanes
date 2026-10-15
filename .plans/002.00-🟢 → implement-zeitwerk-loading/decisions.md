# Decisions: implement-zeitwerk-loading

## D1. Zeitwerk is the loader

Decided by kig, 2026-10-13. Explicit require is not adopted; the loader advice in `docs/REFACTOR.md` is superseded.

## D2. Moved constants get no top-level aliases

Decided by kig, 2026-10-13. Callers move to the new name in the same change.

## D3. The `--` plan-folder separator is out of scope

Decided by kig, 2026-10-13. It has its own plan.

## D4. The plan is narrowed to slimming the four commands

Decided by kig, 2026-10-13.

palpatine-planner blocked on three questions (how to split 1,300 renames over 12 units, where ten unlisted constants go, and what to rename `class Agents` to). It had measured a worktree four weeks behind `main`, still on the `agentilda` code. By then PR #40 had already shipped the Zeitwerk boot and the domain namespaces (with `Agents::Registry`), so all three questions were moot. `spec.md` was rewritten to cover only the remaining task, thinning `create`, `run`, `unblock` and `resync prs`, and the plan goes back to the planner. The old spec and `blocked.md` are kept beside it as `superseded-spec.md` and `superseded-blocked.md`.

## D5. What the plan picks where the spec is open

Taken by palpatine-planner, round 2, 2026-10-14, as the smallest option that meets the spec. Listed in `plan.md` under "Decisions this plan takes": one `OpenLanes::Refusal` failure value; progress drawn by the workflow on STDERR, the deliverable printed by the command; `*Workflow` class names; `start` gets `Engine::StartWorkflow`; `create` keeps opening the editor; the private-method publisher example moves from `run_spec.rb` to the workflow's spec.
