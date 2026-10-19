---
depends_on: ["007.00"]
---

# Plan Dependencies

## Problem

Plans record no dependencies, so the engine can start work whose prerequisites are unfinished and cannot tell which blocked plan holds others up (decisions N6, N7 in `docs/decisions/decisions-on-plan-folder-naming.md`).

### Framings considered

1. **Tool-computed graph, agent-filled declarations.** `spec.md` frontmatter holds `depends_on:`, `Plans::Tree` derives `blocks`, a new agent fills the key.
1. **Gate only, no agent.** Humans write `depends_on:` by hand; the engine merely honours it.
1. **Derive dependencies mechanically** from file overlap or text mentions between specs.

**Chosen: 1.** It is what N6 and N7 decided; framing 2 leaves most plans without the key, and framing 3 produces merge-risk edges that N7 explicitly says are not dependencies. A hand-written key still wins over the agent (N7).

> [!NOTE]
> Ordinals in `depends_on:` are **quoted canonical `"NNN.MM"` strings**. The bare `[034, 045]` in N6 is shorthand only; unquoted, YAML reads it as octal 28 and 37 (Research §1), and a bare `NNN` would mean `NNN.00` (Research §2).

## Goal

After this ships, a plan's prerequisites are declared in its own frontmatter, the tool derives who blocks whom, a plan with an unfinished dependency is not started, plans that others wait on are assigned first, and every plan gets its key filled by `ewoki-linker` before it reaches Building. None of that is possible today: `Plans::Spec.from` drops unknown keys (Research §5) and the dispatcher has no notion of order beyond state.

## Settled decisions

**Delivery.** This spec ships as three plans, each useful on its own: 008.00 (items 1–5 and 12), 008.01 (items 6–9), and 008.02 (items 10, 11, 13). 008.01 depends on 008.00, and 008.02 depends on 008.01.

Decided 2026-10-13 by kig: split into three plans, one per shippable step, because the spec does not fit one pull request and four of its units edit `dispatcher.rb`.

**Grandfathering.** Plans already in 🟡 Building or later when this ships are exempt from the Building invariant, so `resync dirs` never moves them back. They get no `depends_on:` key unless a human writes one.

Decided 2026-10-13 by kig: plans already in Building or later are exempt from the invariant, rather than moved back by `resync dirs` until someone writes the key by hand.

**Cycles.** `Plans::Tree` detects dependency cycles in 008.00 and reports every plan on a cycle as held by a cycle, with the deadlock reason in the report.

Decided 2026-10-13 by kig: `Tree` detects cycles in 008.00, rather than leaving detection to ewoki in 008.01.

## Non-Goals

1. Writing `blocks:` anywhere. It is computed and never stored (N6).
1. Transitive dependencies in the key. Only direct ones are listed (N6).
1. Listing ✅ plans in `depends_on:` (N6).
1. Treating shared files as a dependency; that is a merge risk (N7).
1. Splitting a plan from the choice card. "Split" is offered, but creating the new plan is a separate piece of work.
1. Blocked-plan ageing, 💣 promotion and `deferred/` (N8). A different decision.
1. Running ewoki through the web server as `c3po-operator` does (Research §3).
1. Changing any folder name or adding a state; ewoki's `advances_to` is nil.

## In scope

Each item names its check.

1. **`Plans::Spec#depends_on`**: `nil` when the key is absent, `[]` when empty, an array of strings otherwise. Check: spec for each of the three cases.
1. **Validation**: a non-string entry, or a string that `Ordinal` cannot parse, yields a `Spec` problem rather than a silent value. Check: spec with `[034]` reports a problem; `["034.00"]` does not.
1. **`Plans::Tree` reverse index**: `blocks_of(ordinal)` built from every `depends_on:`; nothing is written to the blocking plan's spec. Check: spec with 050 depending on 034 asserts `blocks_of("034.00") == ["050.00"]` and that 034's `spec.md` is byte-identical.
1. **Blocked-by-dependency gate in the dispatcher**: a plan with any dependency that is not ✅ is not assigned while other plans run. Check: runner spec with two plans, one waiting, asserts only the free one starts.
1. **Order**: plans with a non-empty `blocks` are assigned before plans nobody waits for, within a round. Check: dispatcher spec on candidate ordering.
1. **`agents/ewoki-linker.md`** with frontmatter `precedes: [ready_for_planning, planned]`, `handles: []`, Haiku, low effort. Check: `Agents::Registry` loads it and `Roster` lists it.
1. **Dispatcher ewoki gate**: before candidates are built, a plan in `ready_for_planning` or `planned` whose spec has no `depends_on` key gets ewoki first, selected explicitly, not through `for_status` (Research §3). Check: runner spec asserts ewoki runs once, the folder name is unchanged, and the next round hands the plan to luthen-rael (or r2d2 in `quick`).
1. **Ewoki output contract**: writes only `depends_on:` and a dated ledger note with one reason per dependency. Check: eval case under `evals/cases/ewoki-linker/` plus a deterministic check that only the frontmatter key changed.
1. **Hand-written key wins**: a plan that already has the key is skipped. Check: runner spec.
1. **Building invariant**: `:building` in `status.rb` requires the `depends_on` key, per N7. Plans already in Building or later are exempt (see Settled decisions). Check: `Status` spec; `resync dirs` spec on a plan lacking it, asserting the folder does not move back.
1. **Choice card for more than 3 direct dependencies**: puts the plan under Needs you with options keep all / split / drop some / type an answer. The pick is stored by writing `depends_on:` into `spec.md` plus a dated ledger line naming who chose (Research §6), so the plan is not raised again. Check: spec that a plan with 4 dependencies is held, and that after the answer the key is present and no card is raised.
1. **`list-plans`**: row of 034 shows `blocks 050`. Check: CLI spec on output, with `NO_COLOR=1`.
1. **Docs**: `openlanes docs` regenerates; the decisions doc is amended so N6/N7 use `"NNN.MM"` and name the two gate states. Check: diff of generated document shows the new key.
1. **Linear mapping**: if any new `Status` is needed it appears in `PLACEMENTS`/`UNPLACED`. No new status is planned, so check is that the existing mapping spec stays green.

## Out of scope

| Item | Reason |
| --- | --- |
| Creating a plan from "split the plan" | Needs `Lifecycle::Creator` flow and a human-edited spec; separate plan. |
| Transitive closure stored on disk | Goes stale when a dependency is dropped (N6). |
| Depending on ✅ plans | Already on `main`; `[*]` would serialise everything (N6). |
| Cycle repair | Detection is in scope (see Settled decisions); repair is a human call. |
| Aging and 💣 | Belongs to N8. |
| Linear dependency relations | The Linear export is one-way and not mentioned by N6/N7. |

## Back end / front end

This is a CLI gem; "front end" means the human-facing surface (CLI output and the choice card), "back end" the model and engine. `luke-backend` and `rey-frontend` build as a pair.

| Item | Half | Builds |
| --- | --- | --- |
| 1, 2 `Spec#depends_on`, validation | back end | `lib/openlanes/plans/spec.rb` |
| 3 reverse index | back end | `lib/openlanes/plans/tree.rb` |
| 4, 5 gate and ordering | back end | `engine/dispatcher.rb`, `engine/runner.rb` |
| 6 agent file, `precedes:` | back end | `agents/ewoki-linker.md`, `agents/registry.rb`, `agents/agent.rb` |
| 7, 9 ewoki gate, skip | back end | `engine/dispatcher.rb` |
| 8 output contract, eval | back end | `evals/cases/ewoki-linker/`, checks |
| 10 invariant | back end | `plans/status.rb` |
| 11 choice card | both | back end holds and stores the answer; front end renders the card in the board and Needs you |
| 12 `list-plans` `blocks` | front end | `cli/list_plans/list_plans.rb`, `presentation/reporter.rb` |
| 13 docs | front end | `presentation/documentation.rb`, decisions doc |

## Open questions

Unsettled by leah (Research "Could not settle"):

1. **Missing or closed dependency.** A `depends_on` naming a plan that does not exist or is ✅. Recommendation: unknown ordinal is a `Spec` problem shown in `list-plans`; a ✅ one is ignored with a warning (N6 says only open plans belong).
1. **Threshold of 3.** N7 states it with no justification in any document. Taken as given; make it a constant in one place.

Assumed by this spec:

5. A dependency on a plan whose state is 🅱️ or ⭕️ (blocked) counts as not done, so the dependent waits.
1. A deferred (💤) plan counts as open for this purpose.
1. The ewoki gate applies to the `plan` and `quick` lanes at the same two states; N7's "after yoda in `full`" is the 📋 Ready for Planning state reached after yoda signs.
1. "Needs you" is an existing surface for the choice card; I did not verify its code path.

## Risks to planning or execution

- **Dispatcher size.** `dispatcher.rb` is large and the gate touches candidate building; a regression changes assignment for every plan. Mitigation: gate behind its own method with a spec per lane.
- **Invariant two-way effect.** Adding the Building invariant would move in-flight plans on `resync dirs`; the grandfathering decision exempts plans already in Building or later (Settled decisions).
- **Deadlock.** A plan waiting on a plan that is itself stuck stalls the run at a fixed point with work left. The report must say why.
- **Agent quality.** Ewoki on Haiku at low effort may over-link; the N7 "must name a thing" rule is enforced only by prompt, so the eval cases carry the guarantee.
- **Rename churn.** `precedes:` is a new frontmatter key that `Agents::Registry`, `Roster` and `Executor` must all read; missing one hides ewoki from a report.

## Conclusion

When this ships, `spec.md` frontmatter may carry `depends_on: ["034.00"]`, parsed with a three-way distinction between absent, empty and filled. `Plans::Tree` answers "who does 034 block" from that one index, `list-plans` shows it, and the dispatcher neither starts a plan with an open dependency nor lets an unchecked plan past Ready for Planning or Planned without `ewoki-linker` having filled the key. More than three dependencies go to a human, whose pick lands in the same key.

## Research

Baseline: `RBENV_VERSION=4.0.6 bundle exec rspec` in the worktree reports `2214 examples, 0 failures` (run 2026-10-13). Nothing below needed web search: every claim is a command, a line of code, or both.

### 1. YAML reads `[034, 045]` as octal

Run on Ruby 4.0.6 (Psych, YAML 1.1):

```
YAML.safe_load("[034, 045]")          => [28, 37]
YAML.safe_load("[050, 0x1A, 1_0]")    => [40, 26, 10]
YAML.safe_load("[089]")               => ["089"]
YAML.safe_load('["034", "045"]')      => ["034", "045"]
```

A bare `034` means 28, `050` means 40, `089` is a string. Silent wrong answers, so bare numbers are out.

**Answer:** require quoted strings, and make `Plans::Spec` record a problem for any non-string item. Reading the raw text would duplicate YAML's rules. Quoting also matters for the ordinal form (below).

### 2. Ordinal form

`lib/openlanes/plans/ordinal.rb:27` accepts `NNN` or `NNN.MM`, and a bare `NNN` parses to `minor: 0` (`ordinal.rb:34-37`). So `"034"` means `034.00` and cannot name retroactive plan `034.01`. **Answer:** `depends_on:` entries are quoted canonical ordinals, `"034.00"`. The bare form in this spec's own example is shorthand, and the spec should say so.

### 3. Engine dispatch for an agent not tied to a state

Today the loop only starts agents that handle the plan's state:

- `Agents::Agent#handles?` (`lib/openlanes/agents/agent.rb:86`) reads `handles:`.
- `Agents::Registry#for_status` (`registry.rb:78`) keeps `handles?` agents that are not `read_only?`.
- `Agent#read_only?` (`agent.rb:82`) is `advances_to.nil?`.
- `Dispatcher#next_dispatchable` (`lib/openlanes/engine/dispatcher.rb`, around line 713) builds candidates from `for_status(state)` only.

So an agent with `handles: []` never runs in the loop. `c3po-operator` is the precedent, and it runs through the web server, not the loop. `ewoki-linker` therefore needs a new path in the dispatcher, not just a file in `agents/`.

Precedent for frontmatter that changes behaviour without changing `handles:`: `starts_as` and `holds_at` (`registry.rb:111-112`, read by `dispatcher.rb:869` and `:1176`).

**Answer:** add a frontmatter key, e.g. `precedes: [ready_for_planning, planned]`, and a dispatcher gate. Before `candidates` are built, a plan in one of those states with no `depends_on` key gets `ewoki-linker` first. The folder does not move, because ewoki's `advances_to` is nil. Because `read_only?` agents are excluded from `for_status`, the gate must select ewoki explicitly, not through `for_status`.

### 4. Where the gate sits (contradiction in N7)

N7 says "before a plan's first build agent", then lists "before luthen-rael in plan" and "before r2d2 in quick". luthen-rael handles `ready_for_planning`, not a build state. The states in question:

- `full` and `plan` lanes: luthen-rael runs at 📋 Ready for Planning (`state_machine.rb:37-43` SPINE: `ready_for_planning` → `planned`).
- `quick` lane: r2d2 handles `planned` (`agents/r2d2-mechanic.md:4`), and the lane jumps there (`lanes.rb`, `TARGET`).

**Answer:** gate on either state, so ewoki runs before the first agent that moves the plan toward Building in each lane. The spec should name the two states, not "first build agent".

### 5. The key is invisible to the tool today

`Plans::Spec.from` (`lib/openlanes/plans/spec.rb:134-148`) reads only `lane`, `frontend`, `depth`, `phases` and the note keys. Unknown keys are ignored, so `depends_on:` is silently dropped. Also, `Spec` has no field for "key present", and N6 needs that to tell `depends_on: []` ("checked, none") from a missing key ("not checked yet"). **Needed:** a `depends_on` attribute that is `nil` when the key is absent, and a `Spec` problem for non-string entries (item 1).

### 6. Choice card: where the human's answer is stored

Options checked against the code:

- `blocked.md` `## B<n>` / `## A<n>` (`lifecycle/unblocker.rb`) routes an answer to the blocked agent and drains the question. It is built for "the agent is stuck", not "the plan's dependencies changed", so it does not fit.
- `state.json` messages (`plan_state.rb`, `message!`) are a mailbox between agents, not a decision record.
- The `depends_on:` key itself. Ewoki skips any plan that already has the key (N7). So writing the human's pick there stops the question from being raised again, and the answer is in the file the rest of the engine reads.

**Answer:** store the pick as `depends_on:` in `spec.md` (the drop, the typed answer, or the keep-all), with a dated ledger line saying who chose it. "Split the plan" creates a new plan and is out of scope here.

### 7. Invariant on Building (N7 "cannot enter 🟡 Building without the key")

A `depends_on` check on `:building` in `lib/openlanes/plans/status.rb` also runs in the other direction: `resync dirs` asks the invariant of the state a folder claims (`status.rb` header comment). So every in-flight plan with no key would be flagged, and resync could move it back. This is the grandfathering question in "could not settle" below.

### Contradictions

1. **N7 gate position.** "before the first build agent" vs "before luthen-rael" (luthen-rael is a planner). Resolved in item 4; the spec should name the states.
2. **Ordinal shorthand.** This spec's `depends_on: ["007"]` and N6's `[034, 045]` use bare `NNN`, which means `NNN.00` (item 2). The spec and decisions doc should both say `"NNN.MM"`.
3. **Existing `status.rb` and N7.** N7 says ewoki writes the key; the Building invariant (item 7) would block every in-flight plan without it. The decision and the code disagree until grandfathering is decided.

Production today runs none of this: no `depends_on` parsing, no ewoki, no dispatcher gate. The decisions doc is the target, and the code is the baseline.

### Could not settle

1. Grandfathering: should plans already past Planned, or without the key, be exempt from the Building invariant, or should ewoki backfill them? A product and rollout call, not a code fact.
2. What happens when a `depends_on` names a plan that does not exist or is closed. Error, warning, or ignore? N6 is silent.
3. Whether a dependency cycle (A needs B, B needs A) is detected by the tool or left to ewoki.
4. How many dependencies the choice card allows before "split the plan" is offered: N7 says more than 3, and "3" is not justified in any document I read.

### Findings, Conclusion & References

**Conclusion:** the spec can be written. Answers: quoted canonical ordinals (1, 2); a frontmatter key plus a dispatcher gate on `ready_for_planning` and `planned`, not `handles:` (3, 4); a `depends_on` attribute that distinguishes absent from empty (5); the human's pick stored as the key itself (6). Open: grandfathering, missing-plan handling, cycles, the choice threshold (7 and "could not settle").

**References (all local, observed 2026-10-13):**

- `ruby -ryaml` output, Ruby 4.0.6 (item 1).
- `lib/openlanes/plans/ordinal.rb:27,34-37` (item 2).
- `lib/openlanes/agents/agent.rb:82,86`, `lib/openlanes/agents/registry.rb:78,111-112`, `lib/openlanes/engine/dispatcher.rb` (`next_dispatchable`, `:869`, `:1176`) (item 3).
- `agents/c3po-operator.md:4` (`handles: []`), `agents/r2d2-mechanic.md:4` (item 3, 4).
- `lib/openlanes/plans/state_machine.rb:37-43` (SPINE) (item 4).
- `lib/openlanes/plans/spec.rb:134-148` (item 5).
- `lib/openlanes/lifecycle/unblocker.rb`, `lib/openlanes/plans/plan_state.rb` (`message!`) (item 6).
- `docs/decisions/decisions-on-plan-folder-naming.md`, N6 and N7 (the target).
- `RBENV_VERSION=4.0.6 bundle exec rspec`: `2214 examples, 0 failures`.
