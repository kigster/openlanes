<!-- generated-by: bin/wiki-gen -->

# Agents

_The specialist agents, which state each one handles, and the model it runs on._

**Up:** [Core Concepts](Core-Concepts.md)

______________________________________________________________________

From `openlanes agents list`; read one with `openlanes describe <name>`.

| Agent               | Handles                                           | Advances to                     | Runs on       | Lanes      |
| :------------------ | :------------------------------------------------ | :------------------------------ | :------------ | :--------- |
| `researcher`        | New                                               | Researched                      | haiku/medium  | full       |
| `spec-writer`       | Researched, Retroactive                           | Ready for Planning              | sonnet/medium | full       |
| `planner`           | Ready for Planning                                | Planned                         | opus/high     | full, plan |
| `backend-coder`     | Planned, Building, Changes Requested              | Ready for Review                | opus/high     | full, plan |
| `frontend-coder`    | Planned, Building, Building UI, Changes Requested | Ready for Review                | sonnet/medium | full, plan |
| `chores-coder`      | Planned, Building, Changes Requested              | Ready for Review                | haiku/medium  | quick      |
| `staff-reviewer`    | Ready for Review, In Review                       | Verifying, or Approved & Merged | opus/high     | all        |
| `security-reviewer` | Ready for Review, In Review                       | Verifying, or Approved & Merged | sonnet/high   | full, plan |
| `design-reviewer`   | Ready for Review, In Review                       | Verifying, or Approved & Merged | sonnet/high   | full, plan |
| `verifier`          | Verifying                                         | Approved & Merged               | sonnet/medium | all        |
| `unblocker`         | Technical Block, Product Block, Bomb              | by contents                     | haiku/low     | all        |
| `rebaser`           | stopped rebases, from the harness                 | stages, never moves a plan      | sonnet/high   | all        |
| `copilot`           | none: the control room's read-only copilot        | read-only                       | haiku/low     | all        |

Agent definitions are Markdown files with frontmatter in [`agents/`](https://github.com/kigster/openlanes/blob/main/agents). A plan's `spec.md` frontmatter can change the adapter, model and effort per phase.

<sub>Lifted verbatim from [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md).</sub>

## How agents hand off

An agent never renames its plan folder. It signs the plan's `state.json`, and the harness moves the folder based on the signature:

```bash
openlanes state sign --plan 003 --agent researcher --round 1 --status Started
openlanes state sign --plan 003 --agent researcher --round 1 --status Completed --next spec-writer
openlanes state show --plan 003 | jq '.stages[] | {agent, round, status, model, seconds}'
```

`state.json` lives in every plan folder and is committed with it. It holds the harness's record of each round (adapter, model, effort, tokens, seconds), the agents' signatures, and the messages between them (`openlanes mail send`, `openlanes mail read`). Its shape is [`schemas/plan-state.schema.json`](https://github.com/kigster/openlanes/blob/main/schemas/plan-state.schema.json). Writes go through a lock, so two agents on one plan cannot overwrite each other.

| Status                            | What the harness does                                               |
| :-------------------------------- | :------------------------------------------------------------------ |
| `Completed`                       | moves the folder on, if the files the next state requires are there |
| `Blocked`                         | parks the folder at ⭕, or at 🛑 when the note says `product`       |
| `Almost completed`, `Interrupted` | gives the agent another round, up to its limit                      |

An agent that stops without signing (crashed, timed out, killed) is signed `Interrupted` by the harness, and also `Completed` if the work is on disk anyway. A round left `Started` by a harness that has since died is marked `Interrupted` and picked up by the next run.

`backend-coder` and `frontend-coder` work at the same time, in the same worktree, toward one pull request, and talk through `openlanes mail`. frontend-coder only starts when `plan-frontend.md` has work units, so a back-end-only plan costs one builder.

<sub>Lifted verbatim from [`docs/USAGE.md`](https://github.com/kigster/openlanes/blob/main/docs/USAGE.md).</sub>

## The roster

Read from the frontmatter of every `agents/*.md`, which is what `Agents::Registry` loads. An agent with no `handles:` is called by another part of the run (arbitration, rebasing, review assistance) rather than assigned a state.

| Agent                                                                                             | Handles                                          | Advances to          | Phase         | Model  | Effort | Role                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------ | -------------------- | ------------- | ------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`arbitrator`](https://github.com/kigster/openlanes/blob/main/agents/arbitrator.md)               | _on call_                                        | —                    | arbitration   | opus   | high   | Rules when reviewers and builders disagree, when a plan reaches its rejection cap, and on every review-passed verdict at mvp; reads everything, writes nothing.                        |
| [`backend-coder`](https://github.com/kigster/openlanes/blob/main/agents/backend-coder.md)         | `planned`, `building`, `rejected`                | `ready_for_review`   | build         | opus   | high   | Builds the back-end half of a plan, paired with frontend-coder working the front-end half at the same time, in the same worktree, toward one joint pull request.                       |
| [`chores-coder`](https://github.com/kigster/openlanes/blob/main/agents/chores-coder.md)           | `planned`, `building`, `rejected`                | `ready_for_review`   | build         | haiku  | medium | Does one short, nearly mechanical task straight from spec.md, with no research, rewrite or plan, and leaves it ready for review.                                                       |
| [`copilot`](https://github.com/kigster/openlanes/blob/main/agents/copilot.md)                     | _on call_                                        | —                    | —             | haiku  | low    | The control room's copilot. Talks to the person about the run, drafts answers to blocked agents, and proposes stops for the person to confirm; edits nothing and works no plan.        |
| [`deploy-assessor`](https://github.com/kigster/openlanes/blob/main/agents/deploy-assessor.md)     | `completed`                                      | `approved`           | completion    | opus   | high   | Weighs each ready-to-merge pull request of a completed plan and rules auto (the engine may merge it unattended) or manual (a person merges it).                                        |
| [`design-reviewer`](https://github.com/kigster/openlanes/blob/main/agents/design-reviewer.md)     | `ready_for_review`, `in_review`                  | `approved`           | review        | sonnet | high   | Judges how a plan's diff is organised, against SOLID and the shape of the codebase around it.                                                                                          |
| [`frontend-coder`](https://github.com/kigster/openlanes/blob/main/agents/frontend-coder.md)       | `planned`, `building`, `building_ui`, `rejected` | `ready_for_review`   | frontend      | sonnet | medium | Builds the front-end half of a plan, paired with backend-coder working the back-end half at the same time, in the same worktree, toward one joint pull request.                        |
| [`planner`](https://github.com/kigster/openlanes/blob/main/agents/planner.md)                     | `ready_for_planning`                             | `planned`            | planning      | opus   | high   | Turns a signed-off specification into concurrently executable work units.                                                                                                              |
| [`rebaser`](https://github.com/kigster/openlanes/blob/main/agents/rebaser.md)                     | _on call_                                        | —                    | rebase        | sonnet | high   | Resolves a rebase onto origin/main that stopped on conflicts in a plan's worktree, when the plan's own builder could not; edits and stages only, and the harness continues the rebase. |
| [`researcher`](https://github.com/kigster/openlanes/blob/main/agents/researcher.md)               | `new`                                            | `researched`         | research      | haiku  | medium | Scans the repository for reusable code and the web for existing packages, and adds a short Research chapter to a bare spec.md.                                                         |
| [`security-reviewer`](https://github.com/kigster/openlanes/blob/main/agents/security-reviewer.md) | `ready_for_review`, `in_review`                  | `approved`           | review        | sonnet | high   | Hunts a plan's diff for vulnerabilities and other security holes.                                                                                                                      |
| [`spec-writer`](https://github.com/kigster/openlanes/blob/main/agents/spec-writer.md)             | `researched`, `retroactive`                      | `ready_for_planning` | specification | sonnet | medium | Turns a researched spec.md into a complete specification and leaves a blank plan.md for the planner.                                                                                   |
| [`staff-reviewer`](https://github.com/kigster/openlanes/blob/main/agents/staff-reviewer.md)       | `ready_for_review`, `in_review`                  | `approved`           | review        | opus   | high   | Adversarially checks a plan's documents and diff against what was asked, for correctness, readability, runtime failures and performance.                                               |
| [`unblocker`](https://github.com/kigster/openlanes/blob/main/agents/unblocker.md)                 | `blocked`, `product_blocked`, `bomb`             | —                    | unblock       | haiku  | low    | Folds answered blocks into the documents they were stopping, and retires blocked.md once the last question clears.                                                                     |
| [`verifier`](https://github.com/kigster/openlanes/blob/main/agents/verifier.md)                   | `verifying`                                      | `approved`           | verification  | sonnet | medium | Runs a reviewed pull request's app through its How to test, step by step, and reports with screenshots whether it does what it promises.                                               |

______________________________________________________________________

## Sources

Generated by [`bin/wiki-gen`](https://github.com/kigster/openlanes/blob/main/bin/wiki-gen) v2.0.0 at the commit of 2026-11-07, from:

- [`README.md`](https://github.com/kigster/openlanes/blob/main/README.md)
- [`docs/USAGE.md`](https://github.com/kigster/openlanes/blob/main/docs/USAGE.md)
- [`agents/arbitrator.md`](https://github.com/kigster/openlanes/blob/main/agents/arbitrator.md)
- [`agents/backend-coder.md`](https://github.com/kigster/openlanes/blob/main/agents/backend-coder.md)
- [`agents/chores-coder.md`](https://github.com/kigster/openlanes/blob/main/agents/chores-coder.md)
- [`agents/copilot.md`](https://github.com/kigster/openlanes/blob/main/agents/copilot.md)
- [`agents/deploy-assessor.md`](https://github.com/kigster/openlanes/blob/main/agents/deploy-assessor.md)
- [`agents/design-reviewer.md`](https://github.com/kigster/openlanes/blob/main/agents/design-reviewer.md)
- [`agents/frontend-coder.md`](https://github.com/kigster/openlanes/blob/main/agents/frontend-coder.md)
- [`agents/planner.md`](https://github.com/kigster/openlanes/blob/main/agents/planner.md)
- [`agents/rebaser.md`](https://github.com/kigster/openlanes/blob/main/agents/rebaser.md)
- [`agents/researcher.md`](https://github.com/kigster/openlanes/blob/main/agents/researcher.md)
- [`agents/security-reviewer.md`](https://github.com/kigster/openlanes/blob/main/agents/security-reviewer.md)
- [`agents/spec-writer.md`](https://github.com/kigster/openlanes/blob/main/agents/spec-writer.md)
- [`agents/staff-reviewer.md`](https://github.com/kigster/openlanes/blob/main/agents/staff-reviewer.md)
- [`agents/unblocker.md`](https://github.com/kigster/openlanes/blob/main/agents/unblocker.md)
- [`agents/verifier.md`](https://github.com/kigster/openlanes/blob/main/agents/verifier.md)
