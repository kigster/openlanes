---
depends_on: ["008.00"]
lane: plan
---

# Ewoki Linker

## Problem

Plan 008.00 lets a plan declare `depends_on:` and makes the dispatcher honour it, but nothing fills the key. A plan without it is not gated at all (008.00 `plan.md` decision 4), so in practice most plans run unchecked. Decision N7 (`docs/decisions/decisions-on-plan-folder-naming.md`) assigns that job to an agent, `ewoki-linker`.

This is step 2 of the three-plan delivery settled in `.plans/008.00-🟢 → plan-dependencies/spec.md` ("Settled decisions → Delivery"): 008.00 shipped items 1–5 and 12, this plan is items 6–9, and 008.02 is items 10, 11 and 13. The research behind every item below is in that spec's `## Research` chapter (§3 is the dispatcher path, §5 the frontmatter parser); it is not repeated here.

## Goal

After this ships, every plan reaching 📋 Ready for Planning or ⭐️ Planned without a `depends_on:` key gets `ewoki-linker` once, before the agent that would move it toward Building. Ewoki writes only the key and a dated ledger note giving one reason per dependency. A key a human wrote is never touched.

## Non-Goals

1. The Building invariant and grandfathering (008.02, item 10).
1. The choice card for more than three dependencies (008.02, item 11).
1. Docs regeneration beyond what the new agent file needs (008.02, item 13).
1. Running ewoki through the web server as `c3po-operator` does.
1. Changing any folder name or adding a state: ewoki's `advances_to` is nil.

## In scope

Each item names its check. Numbers follow the 008.00 spec.

6. **`agents/ewoki-linker.md`** with frontmatter `precedes: [ready_for_planning, planned]`, `handles: []`, Haiku, low effort. `precedes:` is read in exactly one place, a new `Agents::Registry#preceding(status)`, which the dispatcher, `Roster` and `Executor` all call; none of them parses the key itself. Check: `Registry` loads it, `#preceding(:planned)` returns it, `Roster` lists it, and its tool grants match an agent that may edit `spec.md` only.
1. **Dispatcher ewoki gate**: before candidates are built, a plan in `ready_for_planning` or `planned` whose spec has no `depends_on` key gets ewoki first, selected explicitly rather than through `for_status` (008.00 Research §3: `read_only?` agents are excluded from `for_status`). Applies to the `full`, `plan` and `quick` lanes alike. Check: runner spec asserts ewoki runs once, the folder name is unchanged, and the next round hands the plan to luthen-rael (or r2d2 in `quick`).
1. **Ewoki output contract**: writes only two things, both in `spec.md`: the `depends_on:` frontmatter key (quoted canonical `"NNN.MM"` strings, `[]` when none), and its ledger entries in the `> [!NOTE]` block that `Plans::Ledger` reads (Started, then Completed), with one reason per dependency on the lines below its Completed entry, each naming the thing the plan needs (N7: shared files are a merge risk, not a dependency). Check: eval case under `evals/cases/ewoki-linker/` plus a deterministic check that the diff to `spec.md` touches only the frontmatter key and the NOTE block, and that no other file in the folder changed except the harness's own `state.json` signature.
1. **Hand-written key wins**: a plan that already has the key, even `[]`, is skipped. Check: runner spec.

## How to tell it's working?

- `bundle exec rspec` and `just lint` stay green.
- `./exe/openlanes agents list` shows `ewoki-linker` with `precedes ready_for_planning, planned`.
- In a temp project with two plans at 📋, where 050's spec mentions 034's parser and has no `depends_on:` key, `./exe/openlanes run --dry-run --isolation shared` reports `would invoke ewoki-linker` for 050 and not for a plan whose spec already has `depends_on: []`.
- `./exe/openlanes evals ewoki-linker` (offline scoring) passes every case.

## Open questions

1. Whether ewoki also runs for a plan already at 🟡 Building or later that lacks the key. Assumed no: those plans are grandfathered (008.00 Settled decisions), and 008.02 decides the invariant.
1. What happens when ewoki fails or is killed. Assumed: the next round tries again, at most once per round, and each attempt is recorded like any other. After **3** failed attempts on the same plan, the harness writes a ⭕️ `blocked.md` question ("ewoki could not link this plan: write `depends_on:` by hand, or retry") instead of retrying forever; a human-written key then ends the gate as usual. The limit is a constant in one place.

## Risks

- **Dispatcher size.** The gate touches candidate building, which every plan goes through. Keep it in its own method with a spec per lane.
- **Over-linking.** Haiku at low effort may link plans that merely share files. The eval cases carry that guarantee; the prompt alone does not.
- **`precedes:` read in several places.** Removed by design: `Agents::Registry#preceding` is the only reader (item 6).
