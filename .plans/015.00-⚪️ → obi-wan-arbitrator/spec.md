---
depends_on: ["005.00", "014.00"]
---

# Obi Wan Arbitrator

## What we are trying to achieve

`obi-wan-kenobi-arbitrator` settles the rejection cap, builders' appeals against review findings, and luke-versus-rey API disputes, and checks every `review-passed` verdict at `medium` and `mvp`.

## Why it matters

Without a tie-breaker a disputed plan loops, and a lenient `review-passed` lets real issues reach `main`.

## What already exists

- Decisions M7–M9 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.

## What research needs to settle

- The appeal format in the ledger, and how a struck finding leaves the review.
- What the engine does with each ruling.

## How to tell it's working?

- Each ruling is a dated entry in `state.json` (a `rulings` array that `schemas/plan-state.schema.json` validates) and one PR comment posted by the engine, never by the agent. `openlanes state show --plan 015` lists it.
- A `review-passed` PR with a critical open finding is downgraded to `review-rejected`: in a spec run against `PlansFixture` and the fake `gh` from #26, a recorded `too_lenient` ruling leaves the PR labelled `review-rejected`, the plan at 🔴, and the rejection count one higher.
- A plan whose hansolo and chewie rejections reach `merge.max_rejections` is not handed back to luke and rey: the next tick runs the arbitrator instead, and a `no_go` ruling leaves the plan at ⭕️ with a `blocked.md` whose `## B1` quotes the ruling, so it shows under Needs you.
- A `go` ruling at the cap moves the PR to `ready-to-merge` through `Vcs::Review` (which still refuses it while CI is red) and the plan back to 🟢 for one last verification.
- A builder signature with the note `appeal: F2 because <reason>` produces exactly one `appeal` ruling; a `struck` ruling makes the next hansolo prompt list F2 as struck, and the PR comment says so.
- The arbitrator's process cannot write: its `allowed_tools` are read-only, `Executor`'s after-check sees no HEAD move, and `git status` in its worktree is clean after a ruling.
- At `top_notch` and `high` (and when `build_quality` is unset) no `review-passed` check runs: zero `passed_check` rulings across a run.

## Framings

1. **A new state.** Add ⚖️ "In Arbitration" to `STATUSES`, route it to the arbitrator through `handles:`, and let the folder name say a ruling is pending.
1. **An engine step.** Keep the plan in the state it is in (🔴 or 👀) and have the dispatcher run the arbitrator as a side call when a trigger fires, then apply the ruling itself, the way `PrOutcomes` (#26) applies a person's verdict.

Framing 2 is chosen. M7 calls the arbitrator read-only, and the registry never routes a state to a read-only agent (`Registry#for_status` drops agents with no `advances_to`, `lib/openlanes/agents/registry.rb:78`, `lib/openlanes/agents/agent.rb:82`); a ruling is also not a place a plan rests, since every outcome lands it in a state that already exists (🔴, 🟢, ⭕️, or unchanged).

## Goal

When reviewers and builders disagree, or a plan hits its rejection cap, the plan stops looping: one read-only Opus agent rules, the engine records the ruling in `state.json` and on the PR, and moves the plan and its label to what the ruling implies. At `medium` and `mvp`, no `review-passed` PR goes on to verification without that check (M9).

## Non-Goals

- The arbitrator writes nothing: no files, no labels, no PR comments, no mail. The engine does all of it (M7).
- Merging. The engine merges under M2 (plan 014's territory); a ruling only sets a label.
- Spec drift. Left to plan aging (M8, `decisions-on-plan-folder-naming.md` N8).
- Blocked product questions. They stay with the human through `blocked.md` and lando (M8).
- Counting a person's GitHub rejection toward the cap. M6 counts hansolo's and chewie's only; #26's `PrOutcomes` already handles a person's `review-rejected`.
- Asking `build_quality` or `max_rejections` at `init`. `build_quality` is plan 011's; M6 says `max_rejections` is not asked.

## In scope

Each item names its check.

1. **The agent.** `agents/obi-wan-kenobi-arbitrator.md`: `handles: []`, no `advances_to` (read-only), `model: opus`, `phase: arbitration`, `allowed_tools` limited to `Read, Grep, Glob` and `Bash(gh pr view:*)`, `Bash(gh pr diff:*)`, `Bash(openlanes state show:*)`, `Bash(openlanes mail read:*)`. *Check:* `openlanes agents list` shows it; a registry spec asserts it is read-only and that `Registry#for_status` never returns it for any status.
1. **The ruling block.** The agent ends its answer with one fenced block, info string `ruling`, holding YAML: `kind` (`cap`, `appeal`, `dispute`, `passed_check`), `pr`, `outcome`, `findings` (`struck: [F…]`, `critical: [F…]`), `winner` (for `dispute`: `luke-backend` or `rey-frontend`), `reason`. `Arbitration::Ruling.parse(text)` reads it from the adapter's final text (`Adapters::Stream#result`, `lib/openlanes/adapters/stream.rb:138`). *Check:* parser spec covers each kind and outcome, a missing block, two blocks, and an outcome not legal for its kind (each refused with a named error and recorded as an Interrupted stage).
1. **The record.** `PlanState#rule!(…)` appends to a new top-level `rulings` array (`at`, `kind`, `pr`, `round`, `outcome`, `findings`, `winner`, `reason`, `trigger`), under the same lock as `sign!`; the schema gains `rulings` and keeps `additionalProperties: false`. *Check:* `plan_state_spec` writes and reads one; a `state.json` without `rulings` still loads, read as empty.
1. **The PR comment.** `Vcs::GitHub#comment(number:, body:, repo:)` (`gh pr comment`), used only by the engine; the comment opens with `⚖️ Ruling (<kind>): <outcome>` and quotes the reason. *Check:* fake-`gh` spec asserts the argv and body; agents still have `gh pr comment` withheld (`FORBIDDEN_COMMANDS`, `lib/openlanes/execution/executor.rb:324-329`).
1. **The cap.** `merge.max_rejections` in `.openlanes.yml` (positive integer), defaulting from `build_quality` per M5 (3/2/2/1), and to 2 when `build_quality` is unset. The count is per plan: hansolo signatures whose note says `rejected`, plus chewie signatures whose note says `rejected` (014 interface, assumed), since the last `cap` ruling. *Check:* config spec for parsing, defaults, and refusing `0`, `-1` and `"two"`; counter spec over a fixture `state.json`.
1. **Triggers.** After each settle the dispatcher asks, per plan, in this order: an unanswered `appeal:` signature note; an unread mail to the arbitrator whose body starts `dispute:` (#28's mailbox); a cap reached at 🔴; a `review-passed` PR at `medium`/`mvp` with no `passed_check` ruling for its head SHA. At most one arbitration per plan per tick, and a plan being arbitrated is not assigned to another agent that tick. *Check:* dispatcher spec per trigger, plus one asserting luke is not started on a capped 🔴 plan.
1. **Applying a ruling.** `Arbitration::Effects#apply(ruling)` is the only code that acts on one:

   | kind / outcome | label (via `Vcs::Review`) | plan | mail |
   | --- | --- | --- | --- |
   | `cap` / `go` | `ready-to-merge` | 🔴 → 🟢 (submit) for one last verification | — |
   | `cap` / `no_go` | stays `review-rejected` | 🔴 → ⭕️; engine writes `blocked.md` `## B1` with the ruling | — |
   | `appeal` / `upheld` | unchanged | unchanged | appellant |
   | `appeal` / `struck` | `ready-to-merge` when no finding stays open, else unchanged | unchanged | appellant and hansolo |
   | `dispute` / winner | unchanged | unchanged | both builders; luke amends `contract.md` |
   | `passed_check` / `fair` | stays `review-passed` | unchanged | — |
   | `passed_check` / `too_harsh` | `ready-to-merge` | unchanged | — |
   | `passed_check` / `too_lenient` | `review-rejected` | 👀 → 🔴, counts toward the cap | luke and rey |

   *Check:* one spec per row against `PlansFixture` and the fake `gh`; a `Vcs::Review` refusal (CI red or pending) leaves label and plan alone and says so in the ruling's PR comment.
1. **A failed final verification after `go`.** The next chewie rejection after a `cap/go` ruling sends the plan to ⭕️ with `blocked.md` instead of 🔴 (M8). *Check:* dispatcher spec.
1. **Findings carry ids and severity.** hansolo's findings comment lists each as `### F<n> [critical|minor] <file>:<line>`; hansolo's prompt is given the struck findings from `rulings` and told not to raise them again. *Check:* agent text diff; an eval case under `evals/cases/hansolo-reviewer/` with a struck finding.
1. **hansolo's cap.** hansolo's verdict table reads `rejected N/<max_rejections>` from its prompt instead of the hard-coded `2`, and "findings after 2 rejections → slop" is removed; `slop` stays for code that is missing, not working, untested or off-spec. *Check:* agent text diff; `Execution::Prompt` spec shows the number.
1. **Appeal format for builders.** luke and rey sign `openlanes state sign … --status Completed --note "appeal: F<n> because <reason>"`. *Check:* agent text diff in both; parser spec for the note.
1. **Evals.** `evals/cases/obi-wan-kenobi-arbitrator/` with at least one recorded case per kind, scored by the ruling parser. *Check:* `openlanes evals` scores them offline.
1. **The control room.** The snapshot carries `rejections: {count, max}` and the latest ruling per plan; the plan row shows "rejected N of M" (M6) and a ⚖️ marker while an arbitration runs. *Check:* snapshot spec; Vitest for the row.

## Out of scope

- The verifier itself, its screenshots and the merge: plan 014 (M1, M2, M14).
- Labels, `openlanes review`, CI gating and human-mode polling: they ship in #26 and are used as they are.
- The mailbox, `mail send` and acks: they ship in #28 and are used as they are.
- Writing `build_quality` into `Config`: plan 011 (its In scope item 1). This plan reads it, nil-safe.
- More arbitration kinds (spec drift, product questions): M8 limits v1 to three, plus M9.

## Back end / front end

| In scope item | Half |
| --- | --- |
| 1–12 | `luke-backend` |
| 13: snapshot fields | `luke-backend` |
| 13: plan row "rejected N of M" and ⚖️ marker | `rey-frontend` |

## Open questions

1. **How the ruling leaves the agent.** (a) A fenced `ruling` block in the final answer, parsed by the engine; (b) a narrow `openlanes ruling` CLI granted as a `Bash(...)` specifier, which writes `state.json` itself. *Recommend (a):* M7 says no write tools, and `c3po-operator` already answers in parsed fenced blocks (`lib/openlanes/live/copilot/cards.rb:11-20`).
1. **Where appeals are written.** (a) A signature note, `appeal: F2 because …`, as M8 says "in the ledger"; (b) a mail to the arbitrator, the same channel as disputes. *Recommend (a)*, keeping M8 literal; disputes use mail because they arise mid-build, when no signature is due.
1. **How a luke-versus-rey dispute is raised.** No mechanism exists. *Recommend:* either builder mails `obi-wan-kenobi-arbitrator` with a body starting `dispute: <contract.md entry>` (#28's `mail send`), and keeps building on its own assumption, as luke's and rey's prompts already say.
1. **Who owns `merge.max_rejections`.** M6 names no plan; 014's seed only says "after `max_rejections` the arbitrator is called". *Recommend:* this plan, since it is the only consumer.
1. **Default cap when `build_quality` is unset.** M5 has no default. *Recommend 2*, matching plan 011's assumed default of `high` and hansolo's current 2.
1. **What the cap counts.** Per plan or per PR, and whether a rejection whose findings were all struck still counts. *Recommend:* per plan, since the last `cap` ruling; a fully struck rejection does not count.
1. **What 014 provides (assumed; its spec is not written yet).** Assumed: chewie signs `Completed, round N (rejected)` or `(verified)` in `state.json`; chewie runs on a plan at 🟢/👀 whose PR carries `ready-to-merge` (or `review-passed` after a `fair` ruling); its rejection moves the plan to 🔴 as hansolo's does. If 014 records verdicts elsewhere, items 5 and 8 change. *Recommend:* confirm against 014's spec before planning.
1. **hansolo never applies `review-passed`.** #26's hansolo table goes from findings to `review-rejected` and from none to `ready-to-merge`. M9 needs a verdict "findings, none critical" → `review-passed`, with a note the dispatcher's `verdict_of` can read (`lib/openlanes/engine/dispatcher.rb:1161-1177`); "passed" matches none of its words today, so the plan would fall through to hansolo's `advances_to`. *Recommend:* this plan adds the row and the note `(passed)`, mapped to staying at 👀.
1. **`merge.by` spelling.** #26 parses `human|auto`; plan 011's spec says `human|agent`, and M4 says "agent". Not this plan's to settle, and it only calls `Config#human_merges?`. *Recommend:* settle it in 011 or #26 before either merges.

## Risks to planning or execution

- **Three unmerged dependencies.** #26 (labels, `Vcs::Review`, fake `gh`), #28 (mailbox ids and acks, `contract.md`) and 014 (unspecified) all change files this plan touches: `agents/hansolo-reviewer.md`, `agents/luke-backend.md`, `agents/rey-frontend.md`, `lib/openlanes/engine/dispatcher.rb`, `schemas/plan-state.schema.json`. Planning against `main` before they merge means rebasing every unit.
- **`dispatcher.rb` is already over 1,200 lines**, and #26 and #28 both add to it. The triggers belong in a separate `Engine::Arbitration` collaborator, called from one line in the settle path.
- **Severity is hansolo's word.** M9's "too lenient" and "too harsh" depend on findings carrying `[critical|minor]`; a hansolo that omits the tag would make every check `fair`. The parser treats an untagged finding as critical, so the failure is strict, not lenient.
- **An Opus call per `review-passed` PR** at `medium` and `mvp`. Keyed by head SHA, so a re-poll does not re-run it.

## Conclusion

When this ships, openlanes has an agent that never writes, and an engine step that runs it when a plan hits `max_rejections`, when a builder appeals a finding, when luke and rey disagree on the contract, and on every `review-passed` PR at `medium` and `mvp`. Each ruling is a dated `rulings` entry in `state.json` and one PR comment, and the engine turns it into a label through `openlanes review`'s rules, a state move, a `blocked.md` for the human, or mail. hansolo's cap comes from `.openlanes.yml` instead of a hard-coded 2, and its findings carry ids that a ruling can strike.

## Research

Method: read `origin/main` at `b2b5176`, decisions M1–M19, the agent contracts, and the open PRs this plan builds on, #26 (`kig/005.00-review-state-labels`) and #28 (`kig/003.00-inter-agent-communication`), with `git show origin/<branch>:<path>`. Plan 014's spec is not written yet (no `kig/014.00-*` branch on origin on 2026-10-14); only its seed on `main` was read. `just lint` and `just test` were run on the worktree. No web sources were needed: every question is about this repository.

### How a ruling can leave a read-only agent

- A read-only agent is one with no `advances_to` (`lib/openlanes/agents/agent.rb:82`), and `Registry#for_status` and `#team_for` exclude it (`lib/openlanes/agents/registry.rb:78`, `:86`). So `handles:` cannot route a state to the arbitrator; the dispatcher must call it. `c3po-operator` is the precedent for an agent outside state routing (`agents/c3po-operator.md:4`, `handles: []`).
- `c3po-operator` grants itself only `Bash(openlanes …:*)` specifiers (`agents/c3po-operator.md:9-19`), passed to `claude` as `--allowedTools` (`lib/openlanes/adapters/claude.rb:76`).
- The adapter keeps the agent's last text as `Stream#result` (`lib/openlanes/adapters/stream.rb:138`); c3po's answers are parsed from a fenced block (`lib/openlanes/live/copilot/cards.rb:11-20`).
- `gh pr comment` and `gh pr edit` are withheld from every agent unless `may:` lifts them (`lib/openlanes/execution/executor.rb:324-329`); `git push` and `gh pr merge` can never be lifted (`:338`).

### Where a ruling is recorded

- `state.json` holds `stages`, `signatures` and `messages` (`lib/openlanes/plans/plan_state.rb:228-230`); the schema forbids other top-level keys (`schemas/plan-state.schema.json:7-8`). A `rulings` array therefore needs a schema change. Squeezing a ruling into a signature `note` would lose the findings and the winner.
- `PlanState#sign!` (`plan_state.rb:163`) and `#message!` (`:188`) both write under `#locked` (`:252`); `#rule!` follows the same pattern.
- `PlanState#ledger` renders signatures only (`:207`), so "the ledger" in M8 means signatures; an appeal written as a signature note is in the ledger.

### The appeal format, and how a struck finding leaves the review

- hansolo's findings today are free text in a PR review or comment, each with file, line and a failing scenario (`agents/hansolo-reviewer.md:32`), with no id and no severity. M9's "cosmetic" vs "critical" (`docs/decisions/decisions-on-merge-modes-and-verification.md:94-95`) has nothing to read.
- So an appeal must name a finding by an id hansolo assigns: `appeal: F<n> because <reason>`, signed through `openlanes state sign --note` (`lib/openlanes/cli/state/subcommands/sign.rb:17`).
- A struck finding leaves the review three ways: the ruling's `findings.struck` in `state.json`; the engine's PR comment; and hansolo's next prompt, which lists struck ids so they are not raised again. If none stays open, the engine sets `ready-to-merge` through `Vcs::Review` (#26, `lib/openlanes/vcs/review.rb:28-47`), which refuses passing labels while CI is red or pending (`:56-63`).

### What the engine does with each ruling

- Labels: only through `Vcs::Review#call` (#26); `ReviewLabel` is the only place label names are spelled (#26, `lib/openlanes/plans/review_label.rb:7-10`).
- PR comments: #26's `Vcs::GitHub` has `swap_label`, `labels`, `checks` and `review_comments` (#26, `lib/openlanes/vcs/github.rb:200,220,230,249`) but no `comment`; this plan adds one.
- State moves: 🔴 → 🟢 is the `submit` path (`lib/openlanes/plans/state_machine.rb:174`); 👀 → 🔴 is `request_changes` (`:185-187`); 🔴 can block (`BLOCKABLE`, `:119`), 👀 cannot. That is why `passed_check/too_lenient` goes to 🔴, and `cap/no_go` goes to ⭕️ from 🔴.
- Needs you lists questions from `blocked.md` and interrupted agents only (`web/src/panels/NeedsYou.tsx:1-2`), so a `no_go` reaches the human as a `blocked.md` the engine writes, answered through the existing unblock path.
- Mail: `Mailbox#append(from:, to:, body:)` (`lib/openlanes/plans/mailbox.rb:104`); #26's `PrOutcomes#mail` already mails 🔴's handlers this way (#26, `lib/openlanes/engine/pr_outcomes.rb:136-142`), a pattern `Effects` can follow.
- Rejections reach the folder through hansolo's note: `verdict_of` maps `reject` → 🔴, `approv` → stays at 👀 awaiting merge, `slop` → 💩 (`lib/openlanes/engine/dispatcher.rb:1083-1093`, `:1161-1177`). Nothing in the engine counts rejections; hansolo counts its own (`agents/hansolo-reviewer.md:36`).

### luke versus rey

- In #28, `implementation-plan.md` becomes `contract.md`; luke owns it, and rey amends an entry when the code disagrees ("the code wins") and mails luke (#28, `agents/luke-backend.md` and `agents/rey-frontend.md`, their "Do" lists). A dispute is two amendments that undo each other; nothing detects it today.
- #28's `openlanes mail send --plan --from --to` (#28, `lib/openlanes/cli/mail/subcommands/send.rb:10-16`) and `mail ack` give a channel with a read flag, so "an unread `dispute:` mail to the arbitrator" is a trigger the engine can test idempotently.

### Contradictions

1. **hansolo's cap vs M6.** `main` and #26 hard-code 2 rejections and send "findings after 2 rejections" to 💩 (`agents/hansolo-reviewer.md:40-43`). M6 makes the cap configurable (3/2/2/1), and M8 sends a capped plan to the arbitrator, not to 💩. Production runs the hard-coded 2.
1. **`review-passed` is never applied.** M3 defines it and M9 depends on it, but #26's hansolo table has no row that sets it (#26, `agents/hansolo-reviewer.md`, verdict table). Until this plan adds one, M9 has nothing to check.
1. **`review-passed` colour.** M3 says `0b6e2e`; #26 changes both the label and the decision doc to `1d76db` (#26, `lib/openlanes/plans/review_label.rb:22-25`). Not this plan's concern; noted because #26 edits the decision doc.
1. **`merge.by` values.** #26 parses `human|auto` (#26, `lib/openlanes/support/config.rb`, `MERGERS`); plan 011's spec says `human|agent` (`.plans/011.00-📋 → init-interview/spec.md:39`).
1. **The seed's `depends_on`.** The seed said `["005", "014"]`, the short form other 📋 specs use. Rewritten as `["005.00", "014.00"]` on the owner's instruction for this plan.

### Could not settle

1. Plan 014's interfaces: how chewie records a rejection, which state it runs at, and whether it reads a `go` ruling. Assumed in Open question 7.
1. Who owns `merge.max_rejections` (Open question 4).
1. The default cap without `build_quality` (Open question 5).
1. Whether a fully struck rejection counts toward the cap (Open question 6).
1. Whether appeals belong in signatures or in mail (Open question 2).

### Findings, Conclusion & References

The arbitrator cannot be routed by state: M7 makes it read-only, and read-only agents never reach `for_status`. It is an engine step with four triggers, a parsed ruling block, a new `rulings` array in `state.json`, and one effects class that turns each ruling into a label through #26's `Vcs::Review`, a state move, a `blocked.md`, or mail through the mailbox #28 extends. Two prerequisites are missing from every branch: findings with ids and severity, and a hansolo verdict that applies `review-passed`.

References:

- `docs/decisions/decisions-on-merge-modes-and-verification.md`: M3 (`:25-38`), M5 (`:50-65`), M6 (`:67-71`), M7 (`:75-77`), M8 (`:79-88`), M9 (`:89-97`).
- `agents/hansolo-reviewer.md`, `agents/c3po-operator.md`, `agents/leah-researcher.md`, `agents/yoda-writer.md` on `main`.
- #26, `kig/005.00-review-state-labels`: `lib/openlanes/plans/review_label.rb`, `lib/openlanes/vcs/review.rb`, `lib/openlanes/vcs/ci_gate.rb`, `lib/openlanes/vcs/github.rb`, `lib/openlanes/engine/pr_outcomes.rb`, `lib/openlanes/engine/pr_watch.rb`, `lib/openlanes/support/config.rb`, `agents/hansolo-reviewer.md`.
- #28, `kig/003.00-inter-agent-communication`: `lib/openlanes/plans/mailbox.rb`, `lib/openlanes/plans/plan_state.rb`, `lib/openlanes/cli/mail/subcommands/send.rb`, `agents/luke-backend.md`, `agents/rey-frontend.md`.
- Plan 014's seed: `.plans/014.00-⚪️ → chewie-verifier/spec.md` on `main`.
- Commands: `just lint` and `just test` on this worktree at `b2b5176`.
