# Continuous Learning for OpenLanes  Agents

> Status: **proposal**, 2026-11-07. Phase 1, the read path, is built (see [Rollout](#rollout)); everything else is proposed. Brainstormed in one session; the calls marked _(my call)_ are the author's, not decisions the maintainer has made yet.

## Why

A software factory should get better the longer it runs on a project. Today every openlanes agent starts each invocation knowing only its `agents/*.md` definition, the plan folder, and the project's `CLAUDE.md` / `AGENTS.md`. When `staff-reviewer` rejects a pull request because the builder mocked the filesystem, nothing stops `backend-coder` from mocking it again on the next plan. The lesson exists (it is in a PR comment and in `state.json`) but nothing carries it forward.

The goal is measurable: **fewer review rounds per plan, fewer `rejected` and `slop` verdicts, and fewer questions asked of a human**, on the same project over time.

### Anti-goals

These would make it a failure even if it technically works:

- **Memory that loosens the factory.** No lesson may waive a review check, grant a tool, or widen the autonomy boundary. Lessons only add care.
- **Self-reinforcing drift.** When openlanes builds openlanes, agents must not be able to rewrite the rules they are judged by, unseen. Every change to memory goes through a human-reviewed pull request (see [Recursion safety](#recursion-safety)).
- **A growing wall of text.** Context is a finite attention budget, and recall degrades as it fills ("context rot", [Anthropic, context engineering][ctx]). An unbounded `memory.md` would make agents worse, not better.
- **A second copy of a fact.** A lesson that is already a rule in `CLAUDE.md`, a lint rule, or a test is deleted from memory, in keeping with "nothing is written down twice".

## What Anthropic does, and what we copy

| Source | Mechanism | What openlanes takes from it |
| --- | --- | --- |
| [Memory tool][memtool] | A client-side `/memories` directory; the model views it first, writes progress and learnings into files; the application owns storage and must validate paths | Memory is plain files the harness controls. The agent reads them; the harness decides what is written |
| Claude Code memory | `CLAUDE.md` hierarchy (user → project → local) for instructions; auto-memory as **one fact per file** with a small `MEMORY.md` index loaded at start | Two scopes (global, project); one lesson per file; a generated index; full text loaded on demand |
| [Agent Skills][skills] | Progressive disclosure: metadata always loaded, body when relevant, linked files when needed; "capture successful approaches and common mistakes" into skills | Lessons show a one-line summary in the prompt and link to the full file. A lesson that grows into a procedure graduates into a skill |
| [Context engineering][ctx] | Smallest high-signal context; structured note-taking; just-in-time retrieval by identifier | A hard token budget per invocation, filled by relevance, never by "everything" |
| [Long-running harnesses][harness], [harness design][harness2] | State lives in files and git; JSON for state models must not casually overwrite; "every component encodes an assumption about what the model can't do", so re-test components as models improve | Lesson metadata in frontmatter; usage counters in JSON; lessons expire unless re-confirmed; evals decide whether memory helps at all |
| Memory poisoning research ([arXiv 2607.14611][poison]) | Planted instructions in persistent memory compromise later sessions; the model is not a security boundary | Lessons from untrusted text are quarantined; enforcement stays in `Executor` and `Boundary`, never in memory |

## The design

### Two scopes

| Scope | Where | Committed | Holds |
| --- | --- | --- | --- |
| **Project** | `.openlanes/memory/` in the repository | Yes | How _this_ codebase wants things done: test idioms, layering, naming, refactoring thresholds, which findings reviewers keep raising |
| **Global** | `${XDG_CONFIG_HOME:-~/.config}/openlanes/memory/` _(my call: the XDG config dir rather than `~/.local/config`, which is not an XDG location; openlanes already follows XDG for state in `events/location.rb`)_ | No | The human's own preferences and decisions that recur across projects: commit style, how much to ask before acting, rejection reasons seen in two or more projects |

Project memory wins over global when they disagree, the same way a project `CLAUDE.md` overrides the user one.

### One shared memory, addressed by role, not one file per agent

_(my call)_ Neither a single file nor fifteen per-agent files:

- **Per-agent files fail the main case.** The lesson is learned by the _reviewer_ and needed by the _builder_. With per-agent memory, `staff-reviewer` would remember that it rejected mocked filesystems while `backend-coder` never hears of it.
- **One file fails at scale and in git.** Two people adding lessons on two branches edit the same file and conflict; one growing file also defeats the token budget.

So: **one lesson per file**, each declaring who it is for.

```markdown
---
id: L-0042
title: Specs build real .plans trees, never mock the filesystem
applies_to: [backend-coder, frontend-coder, chores-coder]   # agent names, or phases: [build, review]
checked_by: [staff-reviewer]      # reviewers who should cite it when it is broken
kind: practice                    # practice | decision | pitfall | struck
severity: high                    # how much a violation costs a review round
source:                           # evidence; a lesson without evidence is not admitted
  - pr: 181
    finding: "spec stubs File.read; tests the fake"
  - pr: 187
    finding: "same, Dir.glob stubbed"
status: active                    # candidate | active | graduated | retired
supersedes: []
confirmed: 2026-11-04             # last time evidence or a human re-confirmed it
---

Specs create plan trees with `PlansFixture` and the `:tree` tag in a temp directory.
Stubbing `File`/`Dir` makes the spec test the stub. Twice rejected for this.
```

The `applies_to` list routes one fact to every role that needs it. `checked_by` is the other half: the reviewer is told to cite `L-0042` when it finds the violation, and that citation is how we measure whether the lesson works (see [Measuring it](#measuring-it)).

`kind: struck` generalises what the arbitrator already does: today a struck finding goes into one plan's reviewer prompt as "never to be raised again" (`Execution::Prompt#review_section`). A struck finding that recurs across plans becomes a project lesson telling reviewers not to raise it.

`kind: decision` holds a human's answer to a blocked question that will come up again ("Should new CLI commands support `--json`?" → yes). That serves openlanes' own principle of minimal human intervention: a question answered once is not asked twice.

### Layout

```
.openlanes/memory/
  lessons/L-0042-real-plans-trees-in-specs.md     # one lesson per file, the source of truth
  inbox/2026-11-07-pr-193-staff-reviewer.md        # candidates the curator proposed, not yet active
  usage.json                                       # cited/violated counters, written by the harness only
```

There is no hand-written index. `openlanes memory list` and the prompt section are derived from the frontmatter, in keeping with "nothing is written down twice".

### How lessons reach an agent

A new `memory_section` in `Execution::Prompt`, next to `review_section` and `journal_section`:

1. Select active lessons whose `applies_to` names this agent or its phase, from project and global scope.
2. Rank by severity, then by how often the lesson was violated recently, then by recency of confirmation.
3. Fill a budget (_my call_: 1,500 tokens by default, `memory.budget` in `.openlanes.yml`) with **one line per lesson**: id, title, path. Agents read the full file only when it bears on the task, the progressive disclosure that skills use.
4. Reviewers additionally get their `checked_by` lessons as an explicit checklist and are asked to cite ids in findings.

`openlanes run --no-memory` and `memory.enabled: false` turn it off. That switch is what lets us measure whether memory helps at all.

### Where lessons come from

openlanes already records the signals; nothing new has to be captured during a run:

| Signal | Recorded today in | Becomes |
| --- | --- | --- |
| `rejected` verdict with findings | reviewer stage in `state.json`; PR comments (each finding has a failure scenario) | `pitfall` / `practice` candidates for the builders |
| `slop` verdict | `rewrite.md` | high-severity candidates |
| Arbitrator struck findings | the arbitration ruling | `struck` candidates for the reviewers |
| Answered blocked questions | `blocked.md`, drained by the unblocker | `decision` candidates |
| Verifier failure, CI red after "passed" | verifier stage, labels | `pitfall` candidates for builders and reviewers |
| Human edits to an agent's branch before merge | the diff between the last agent commit and the merge commit | candidates; the strongest signal, since a person spent time fixing it |

### The curator, and why agents never write memory directly

A new agent, `curator` _(name is my call)_, runs when a plan reaches a terminal state (merged, rewrite, discarded) and, cheaply, after each rejected round. It reads the signals above for that one plan and writes **candidates** into `.openlanes/memory/inbox/`: each one a proposed lesson with its evidence, or a proposed `supersedes:` / `retire` of an existing lesson.

It does not activate anything. Promotion is a separate, deterministic step in the harness:

- A candidate whose finding matches an existing lesson adds evidence to it and bumps `confirmed`, and is not a new lesson.
- A candidate seen in **two or more plans** (_my call_: 2), or explicitly approved by a human, is promoted to `active`.
- Everything that changes `lessons/` goes out as **its own pull request** ("memory: 3 new lessons, 1 retired"), opened by `Publisher` like any build. A human reviews and merges it. `gh pr merge` stays ungrantable.

That keeps memory under the same rules as code: versioned, attributable, reversible, reviewed.

### Many people on one project

Memory is committed, so several people's factories will add to it concurrently.

- **Additions don't conflict** in git: every lesson is its own file. Ids are allocated like plan ordinals, highest id plus one, and a collision found at merge time is renumbered by `openlanes memory resync`, the way `resync dirs` reconciles plan folders.
- **Disagreements are semantic, not textual.** When the curator finds two active lessons that contradict each other ("extract a class at 100 lines" against "don't split until a second caller exists"), it does not pick one. It opens a blocked question for a human, and the answer becomes a `decision` lesson that `supersedes:` both.
- `usage.json` is merge-friendly (counters keyed by lesson id, summed on conflict) or kept local and gitignored _(open question below)_.

### Global memory

Global lessons are the human's own. They are never committed and never leave the machine. A project lesson is **proposed** for global scope when the curator sees the same lesson active in two or more projects on this machine, and the human approves it with `openlanes memory promote L-0042 --global`. Global memory is read-only to every agent.

### Graduation: memory is a waiting room, not a destination

A lesson is a rule the factory does not yet enforce. The best lesson is one that disappears because something deterministic took its place. Anthropic's skills guidance says the same: deterministic work belongs in code, not tokens.

| A lesson that is... | graduates to | and is then |
| --- | --- | --- |
| checkable by a tool | a RuboCop cop, a lint rule, a spec, a CI check | `graduated`, removed from prompts |
| a stable project convention | a line in the project's `CLAUDE.md` / `AGENTS.md` | `graduated` |
| a multi-step procedure | a skill under `skills/` | `graduated` |
| about one agent's craft | that agent's `agents/*.md` (human PR only) | `graduated` |
| not violated or cited in N plans (_my call_: 15) | nothing | `retired` (kept in git history) |

`openlanes memory report` lists graduation candidates: lessons violated often (worth enforcing) and lessons never cited (worth retiring).

### Measuring it

Without measurement, memory is just a longer prompt. openlanes already has what it needs:

- **Per-plan outcomes** from `state.json` and `pr_reviewed` events: review rounds to approval, `rejected`/`slop` counts, questions asked, tokens spent.
- **Per-lesson usage** in `usage.json`: how often a reviewer cited the lesson as _violated_ after it was active. A lesson that is still violated is not working: reword it or graduate it to a check.
- **Evals** (`evals/cases/<agent>/`): a lesson that came from a real rejection becomes an eval case (the rejected diff is the `fail/` fixture, the fixed one `pass/`). `openlanes evals --live` with and without memory answers "does memory help this agent?" before the factory trusts it.

The headline metric: _rounds-to-approval per plan, rolling average over the last 20 plans, with memory on against a `--no-memory` baseline._

## Recursion safety

openlanes building openlanes is the hardest case: the agents' memory, their definitions and the harness that enforces their boundary all live in the repository they are changing. The guarantees:

1. **Agents cannot write active memory.** The curator writes only to `inbox/`. Promotion is harness code, and every change to `lessons/` arrives as a human-reviewed PR. The read path enforces this already: agents are told only the lessons on `origin/<default branch>`, so whatever an agent writes into a checkout stays out of every prompt until a person merges it.
2. **Memory cannot grant anything.** `Executor` builds tool grants from `agents/*.md` frontmatter and `UNGRANTABLE`, never from memory text. A lesson that mentions permissions, tools, network or pushing is rejected at promotion (a deterministic check, not a model's judgement).
3. **Memory cannot remove a check.** Reviewer lessons may add checks (`checked_by`) but cannot waive one; only the arbitrator's existing per-plan strike does that, and its cross-plan form (`kind: struck`) still needs human promotion.
4. **Untrusted text is quarantined.** Findings from PR comments by anyone other than openlanes' own reviewers or the repo's maintainers (third-party bots, drive-by commenters) produce candidates marked `untrusted` that require explicit human approval, closing the memory-poisoning path.
5. **The agents directory is off limits.** Graduation into `agents/*.md` or `skills/` is proposed in the report and made by a human. The curator's `writes:` frontmatter lists only `.openlanes/memory/inbox/`.
6. **A kill switch with a baseline.** `--no-memory` gives an A/B comparison, and reverting one memory PR undoes a bad lesson completely.

With those, the factory improving itself is the same as the factory building any feature: proposals in, human merge, measurable effect, reversible.

## Rollout

- [x] **0. Baseline.** Already there: `openlanes events report` gives completion and intervention rates and PR outcomes (approved, rejected, merged) from the event log. Still missing: rounds-to-approval per plan, and tagging each run with whether memory was on, so the report can compare the two.
- [x] **1. Read path.** Built: the lesson format, `OpenLanes::Memory` (`Lesson`, `Library`, `Section`, and the two sources `Committed` and `Folder`), the prompt section with its budget, project and global scopes, `run --no-memory`, `eval --live --no-memory`, `openlanes memory list [--agent]`. Lessons are hand-written; reviewers are asked to cite ids. Deferred: `usage.json` citation counting.
  - Recursion safety already holds for the read path (PR 196 security review): project lessons are read from the commit `origin/<default branch>` names when a run starts, never from a checkout, and kept for the whole run; a lesson without `status: active` is a candidate; ids, titles and names must be single plain lines; symlinks, unreadable and non-UTF-8 files are skipped and reported; the prompt fences the lessons as quoted data the rest of the prompt overrules.
- [ ] **2. Curator.** The agent, the inbox, deterministic promotion (2+ plans), the memory PR through `Publisher`, the permission and untrusted-text checks.
- [ ] **3. Global scope.** XDG directory, `promote --global`, cross-project proposals.
- [ ] **4. Graduation and evals.** Graduation report, lesson-to-eval-case generation, retire on disuse.

Phases 1 and 2 are each a plan of their own; 0 and 3 are small.

## Open questions for the maintainer

1. **Location of project memory:** `.openlanes/memory/` (next to `.openlanes.yml`, needs a new dot-directory) or `docs/memory/` (visible, reviewable like docs)?
2. **`usage.json`: committed or local?** Committed gives the team shared evidence but churns on every run; local is quiet but each person measures alone.
3. **Promotion threshold:** two plans, or always a human, at least until the curator has earned trust?
4. **Should memory PRs be bundled** with the plan PR that produced them (one review), or always separate (cleaner history, more PRs)?
5. **Global scope location:** `~/.config/openlanes/memory/` as proposed, or keep `~/.local/config/openlanes/memory-shared.md` as first suggested?

[memtool]: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
[ctx]: https://anthropic.com/engineering/effective-context-engineering-for-ai-agents
[skills]: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
[harness]: https://anthropic.com/engineering/effective-harnesses-for-long-running-agents
[harness2]: https://anthropic.com/engineering/harness-design-long-running-apps
[poison]: https://arxiv.org/abs/2607.14611
