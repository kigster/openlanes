---
depends_on: ["008.00"]
starts: planning
---

# Ewoki Linker

## Problem

Plan 008.00 lets a plan declare `depends_on:` and makes the dispatcher honour it, but nothing fills the key. A plan without it is not gated at all (008.00 `plan.md` decision 4), so in practice most plans run unchecked. Decision N7 (`docs/decisions/decisions-on-plan-folder-naming.md`) assigns that job to an agent, `ewoki-linker`.

This is step 2 of the three-plan delivery settled in `.plans/008.00-🟢 → plan-dependencies/spec.md` ("Settled decisions → Delivery"): 008.00 shipped items 1–5 and 12, this plan is items 6–9, and 008.02 is items 10, 11 and 13. The research behind every item below is in that spec's `## Research` chapter (§3 is the dispatcher path, §5 the frontmatter parser); it is not repeated here.

## Goal

After this ships, every plan whose specification is finished passes through a new state, 🔗 Ready for Linking, where `ewoki-linker` writes its `depends_on:` key before the planner starts; the plan moves on to 📋 only once the key is answered. Plans that were already at 📋 Ready for Planning or later when this shipped are linked by `openlanes link`. Ewoki writes only the key and a dated ledger note giving one reason per dependency. A key a human wrote is never touched.

> [!NOTE]
>
> Amended on 2026-10-23, in review of PR #114: the build adds the 🔗 state instead of the `precedes:` hook this spec first described (D1 places linking "wherever the spec has finished being written"). Non-Goal 5, items 6 and 9, the branch-and-PR flow and the How-to-tell list were changed to match. The product owner confirms or reverses this through `blocked.md` B2.

### When it runs

The dependency graph between plans is a new concept, and its most important use is the ability to apply a topological sort to interdependent plans, so that plans other plans depend on are built first. Not every plan will always depend on one or more other plans; therefore, when topologically sorted, unimplemented plans can form several independent DAGs. This determines which plans can be implemented concurrently (disjoint DAGs) and which must wait for other plans to merge before they can be on the board.

> [!important]
>
> The linker should run only in the primary repo, which is where plans are created, committed and pushed, and never from a worktree (except after the plan becomes a task in progress).
>
> It should run after a new plan is created and briefed, and it should run on the entire corpus of plans that are yet to be done and that are missing `depends_on:` completely or whose value is `[]`.
>
> It also scans and adds this key to plans without it, or with the value `[]`, before the openlanes engine starts up and begins to implement plans, choosing which to start. The linker should skip any plans with `depends_on: [ non-empty ]` and only double-check the plans with an empty value or without the `depends_on` key entirely. The keyword `none` inside the square brackets should be inserted if no prior or future plan is a dependency.

### New Command

Build a new command that refuses to run in a worktree and can only run in the main repo on the main branch. Moreover, it performs `git pull` on main before running, to ensure the plans are complete.

The command is called `link`, and it accepts `--plans`, in which case only those plans are checked for being dependent on others. Without this flag, all non-archived plans are checked according to the rules above.

If a missing dependency declaration is found, it is written into the plan, as many as necessary. The agent notifies the dispatcher that linking is complete with one of two outcomes:

1. No new links are found. This completes the linker's operation, and if it was invoked as a command, it exits reporting that no new links were found.

2. If new links are found, it reports how many plans it linked and asks the user to commit the current branch. `link` commits nothing. The `$USER/plan-linking-NNN.MM` branch, its pull request and the harness merge of D3 are deferred to a follow-up plan (Non-Goal 6).

## Topological Sort

When the engine starts without specific plans passed as arguments, it must sort the todo plans using tsort, based on the declared dependencies. Already on `main` before this plan: `Plans::Dependencies#order` sorts each dependency group topologically (Kahn's algorithm, ordinal as tie-break), and `#head` gives each group one plan at a time. This plan adds no second sort.

In a DAG of connected plans, only the first one can be worked on, until it merges, before any work on the second begins.

A plan that is first in a separate DAG can also be worked on in parallel, up to the number of workers specified.

Finally, two or more plans with the same `depends_on` plan(s) can run in parallel once their dependencies are completed.

## Non-Goals

1. The Building invariant and grandfathering (008.02, item 10).
1. The choice card for more than three dependencies (008.02, item 11).
1. Docs regeneration beyond what the new agent file needs (008.02, item 13).
1. Running ewoki through the web server as `copilot` does.
1. Changing any folder name or adding a state beyond the one 🔗 `ready_for_linking` state ewoki handles (amended 2026-10-23).
1. The `$USER/plan-linking-NNN.MM` branch, its pull request and the harness merge of D3 (amended 2026-10-23: a follow-up plan).

## In scope

Each item names its check. Numbers follow the 008.00 spec.

6. **`agents/ewoki-linker.md`** with frontmatter `handles: [ready_for_linking]`, `advances_to: ready_for_planning`, `confined_to: [spec.md]` (amended 2026-10-23; was `precedes:`). The harness leaves 🔗 only when `spec.md` answers `depends_on:`. Check: `Registry` loads it, `Roster` lists it as `Ready for Linking → Ready for Planning`, and its tool grants are those of an agent that may edit `spec.md` only.
1. **Dispatcher ewoki gate** (dropped by D1): before candidates are built, a plan in `ready_for_planning` or `planned` whose spec has no `depends_on` key gets ewoki first, selected explicitly rather than through `for_status` (008.00 Research §3: `read_only?` agents are excluded from `for_status`). Applies to the `full`, `plan` and `quick` lanes alike. Check: runner spec asserts ewoki runs once, the folder name is unchanged, and the next round hands the plan to planner (or chores-coder in `quick`).
1. **Ewoki output contract**: writes only two things, both in `spec.md`: the `depends_on:` frontmatter key (quoted canonical `"NNN.MM"` strings, `[]` when none), and its ledger entries in the `> [!NOTE]` block that `Plans::Ledger` reads (Started, then Completed), with one reason per dependency on the lines below its Completed entry, each naming the thing the plan needs (N7: shared files are a merge risk, not a dependency). Check: eval case under `evals/cases/ewoki-linker/` plus a deterministic check that the diff to `spec.md` touches only the frontmatter key and the NOTE block, and that no other file in the folder changed except the harness's own `state.json` signature.
1. **Hand-written key wins**: a plan whose key holds `[none]` or plan numbers is skipped; a missing key and `[]` are re-checked (D2). Check: runner spec.

## Decisions

### B1 (answered) — Where the linker runs

Item 7 runs ewoki in each plan's worktree, while "When it runs" says the linker runs only on `main` in the primary repo. Which holds?

### D1 (decision) — It Depends on When

- Answered on 2026-10-20
- By the product owner

Whereever the spec has finished being written, and is ready to go into planning during the automated process.

During the creation of new plans (at the end of the create command but only on that plan). 

The `link` command should ideally run on `main`, and should print a warning when it's run in a worktree. But it can also run in a worktree. 

### B2 (answered) — What "no dependencies" looks like

Item 8 writes `[]` for "don't know", and item 9 never touches an existing key. "When it runs", any [] are checked. 

### D2 (decision) — `[none]` means checked, none

- Answered on 2026-10-20
- By the product owner

The ones that are skipped are either the ones that have plans, eg `[ "008.01", "009.00" ] or it has the word "none": [ none ]

Write `depends_on: [none]` for "checked, none". Re-check a missing key and `[]`. Skip `[none]` and any non-empty list. `Spec#depends_on` reads `[none]` as no edges.

### B3 (answered) — Auto-merging the linking PR

The linking PR could be merged by the dispatcher on green CI. Today `gh pr merge` is in `UNGRANTABLE`, and CLAUDE.md keeps merging out of agents' reach. Who merges?

### D3 (decision) — Harness merges, narrowly

- Answered on 2026-10-20
- By the product owner

The harness, never an agent, merges the linking PR on green CI through the `GitHub` seam. It does so only when the diff touches nothing but `depends_on:` lines in `.plans/*/spec.md`. `gh pr merge` stays in `UNGRANTABLE` for agents.

### B4 (answered) — What topological sort adds to the existing gate

008.00 already holds a plan whose `depends_on:` names a plan not yet ✅. What does tsort add?

### D4 (decision) — Order only

- Answered on 2026-10-20
- By the product owner

Order only. With no plan arguments, `run` sorts candidates by `TSort` over `Dependencies`, with the roots of each disjoint DAG first and the ordinal as tie-break. Holding stays with the 008.00 gate.

### B5 (answered) — Split into plans

Items 6–9, `link`, the main-branch guard, `git pull`, the branch and PR flow, the run pre-pass and tsort come to about twelve units. Should this be one plan or several?

### D5 (decision) — Two plans

- Answered on 2026-10-20
- By the product owner

Everything is in this one plan.

### B6 (answered) — System lane in the UI

The spec says the UI "can add" a dedicated lane for system tasks. In scope or not?

### D6 (decision) — Out of scope

- Answered on 2026-10-20
- By the product owner

Out of scope. The System lane is a follow-up for 008.02 or the web plans.

## How to tell it's working?

- `bundle exec rspec` and `just lint` stay green.
- `./exe/openlanes agents list` shows `ewoki-linker` as `Ready for Linking → Ready for Planning`.
- In a temp project with a plan at 🔗 whose spec has no `depends_on:` key, `./exe/openlanes run --dry-run --isolation shared` reports `would invoke ewoki-linker` for it, and not for a 🔗 plan whose spec already has `depends_on: [none]`.
- In a temp project with two plans at 📋, where 050's spec mentions 034's parser and has no `depends_on:` key, `./exe/openlanes link -n` prints `would invoke ewoki-linker for 050.00` and not for a plan whose spec already has `depends_on: [none]`.
- `./exe/openlanes evals ewoki-linker` (offline scoring) passes every case.

## Open questions

1. Whether ewoki also runs for a plan already at 🟡 Building or later that lacks the key. Assumed no: those plans are grandfathered (008.00 Settled decisions), and 008.02 decides the invariant.
1. What happens when ewoki fails or is killed. Assumed: the next round tries again, at most once per round, and each attempt is recorded like any other. After **3** failed attempts on the same plan, the harness writes a ⭕️ `blocked.md` question ("ewoki could not link this plan: write `depends_on:` by hand, or retry") instead of retrying forever; a human-written key then ends the gate as usual. The limit is a constant in one place.

## Risks

- **Dispatcher size.** The gate touches candidate building, which every plan goes through. Keep it in its own method with a spec per lane.
- **Over-linking.** Haiku at low effort may link plans that merely share files. The eval cases carry that guarantee; the prompt alone does not.
- **A plan leaving 🔗 unlinked.** Removed by design: the edges out of 🔗 are guarded on `Spec#linked?`, so a linker that times out or writes nothing leaves the plan at 🔗.
