---
depends_on: ["008.00"]
---

# Plan Aging and Bombs

## What we are trying to achieve

Blocked plans age. One that others depend on becomes 💣 after 7 days unanswered and halts the run; one nobody depends on moves to `deferred/` after 14 days. The control room shows a split notice with Respond and Pause and Discuss.

## Why it matters

In equilibris-app 9 of 14 open plans were blocked, some for months, and nothing forced a decision.

## What already exists

- Decisions N8–N10 in `docs/decisions/decisions-on-plan-folder-naming.md`.
- The `blocks` index from plan 008.
- `lib/openlanes/lifecycle/unblocker.rb` and `lando-broker`: answering blocks.
- The copilot panel (PR #7), which Pause and Discuss opens.

## What research needs to settle

- The 💣 state: its event in the `aasm` block, its invariant, its place in `linear/mapping.rb`.
- `plans.aging_since` in `.openlanes.yml`, and the clock starting from the date a plan became blocked.
- How `run` halts and how `--ignore-bombs` and "Resume anyway for 24 h" lift the halt.

## How to tell it's working?

- With `aging_since` set to today, nothing ages. Backdate it, and a blocked plan with dependents turns 💣 and `lanes run` exits non-zero naming it.
- The notice shows `blocked.md` on the left and an answer box on the right; Respond writes into `blocked.md`, and work resumes on the next round.
- A blocked plan with no dependents moves to `deferred/` after 14 days.

## Framing

Two ways to see the problem:

1. **Policy at the edges.** Aging is a sweep the engine runs once per round. It fires explicit events (`bomb`, `defer`) from blocked plans, and 💣 is an ordinary folder state with a pure invariant.
1. **Derived state.** 💣 is computed on read from the clock and the `blocks` index, and `resync dirs` renames folders as days pass.

Chosen: **1**. A wall-clock invariant would rename folders with no event, which breaks "asking a question about a folder must never fire one" (`CLAUDE.md`; research contradiction 5).

## Goal

A blocked plan stops being able to sit for months. After 7 days unanswered, a blocked plan that other plans depend on becomes 💣 and halts new work, so a human must answer, pause or consciously override. After 14 days unanswered, a blocked plan nobody depends on moves to `deferred/` as 💤. The control room shows a notice with the question and an answer box, so the decision is a few clicks, not a hunt through folders.

## Non-Goals

- Not a general scheduler or reminder system: no notifications by email, chat or push.
- Not auto-answering. Nothing guesses an answer to `blocked.md`; aging only changes state.
- Not re-speccing, splitting or discarding plans. Pause and Discuss opens the copilot and changes nothing on disk (N10).
- Not building the dependents index. That is plan 008; this plan consumes `blocks`.
- Not renaming emoji to the N2 set (⭕ 🛑 💤). Plan 009 uses the forms production runs today.
- Not aging plans in any state other than ⭕️ and 🅱️.

## In scope

Each item is checkable by a spec or a command.

1. **State.** `:bomb` exists in `STATUSES` (`status.rb`), with emoji 💣 (U+1F4A3), `requires: %w[blocked.md]`, and an invariant "blocked.md present" only (no clock). Check: `openlanes states` lists it, `openlanes docs` regenerates, `mapping_spec.rb` stays green.
1. **Event.** A `bomb` event moves `blocked` and `product_blocked` to `:bomb`; answering returns the plan to its prior path via `lifecycle/unblocker.rb`. Check: `state_machine_spec` covers edges in and out.
1. **Linear.** 💣 appears in exactly one of `PLACEMENTS` or `UNPLACED` in `linear/mapping.rb`.
1. **Config.** `.openlanes.yml` accepts `plans.aging_since` as a date; a malformed date or an unknown key under `plans:` raises with the key named. Absent means no floor. Check: `config_spec`.
1. **Clock.** Age is measured from the later of the plan's `blocked` signature `at` in `state.json` (falling back to `blocked.md` mtime, as `web/live/snapshot.rb:279-280` does) and `aging_since`. With `aging_since` set to today, nothing ages.
1. **Sweep.** Once per round, before assignment, a sweep fires `bomb` for blocked plans with dependents past 7 days, and `defer` for blocked plans without dependents past 14 days. The limits are constants in one place. Check: runner spec with backdated `state.json`.
1. **Auto-defer.** The sweep writes `delayed.md` with the trigger "revisit after the block is answered" so the `:deferred` invariant holds.
1. **Halt.** While a 💣 exists, `Dispatcher` assigns nothing new; agents already running finish. `openlanes run` exits non-zero and names each 💣 plan on STDERR. `lanes start` stays up and idle.
1. **Lift.** `run --ignore-bombs` disables the halt for that run. The control-room "Resume anyway for 24 h" writes a timestamped expiry into `state.json`; the halt is lifted until it passes, with no config edit.
1. **Notice.** The control room shows a full-width notice per 💣: `blocked.md` rendered on the left; answer box on the right with **Respond** and **Pause and Discuss**.
1. **Respond.** A new command kind in `live/commands.rb` writes the answer into `blocked.md`; the next round's `unblocker` folds it in.
1. **Pause and Discuss.** A new command kind holds every running agent (reusing `hold` from `execution/control.rb`) and opens the copilot with the plan loaded. No file changes.

## Out of scope

- Dependents index and `depends_on:` canonical form: plan 008 owns it; this plan depends on it.
- `ewoki-linker`: N7, a separate plan.
- N2 emoji migration: separate plan; building both here would couple two renames.
- Git rename date as the clock source: no code reads git dates today, and `state.json` holds the same moment.
- Aging for 🔎, 📋 or any non-blocked state: the decision doc only ages blocks.

## Back end / front end

| Item | Half | Builder |
| --- | --- | --- |
| State, event, Linear mapping | back end | `luke-backend` |
| Config key `plans.aging_since` | back end | `luke-backend` |
| Clock, sweep, auto-defer | back end | `luke-backend` |
| Halt, exit code, `--ignore-bombs` | back end | `luke-backend` |
| Resume-anyway expiry in `state.json` | back end | `luke-backend` |
| Respond and Pause and Discuss command kinds | back end | `luke-backend` |
| Notice, answer box, buttons, copilot hand-off | front end | `rey-frontend` |
| Resume-anyway button | front end | `rey-frontend` |

The pair agrees on the two command payloads (`respond`: plan, text; `pause_discuss`: plan) and on the snapshot field that lists bombs.

## Decisions taken here

Settled from the research recommendations. Reopen any of them only through a human.

1. Clock source is `state.json` `blocked` `at` (research Q1).
1. The sweep writes `delayed.md` when auto-deferring (Q2).
1. 💣 is entered by an explicit sweep event, not by `resync dirs` (Q3).
1. `openlanes run` exits 1 on a 💣 (Q5), matching N9; `lanes start` idles.
1. Resume-anyway is stored in `state.json` with an expiry timestamp (Q6).
1. `plans:` is validated key by key, and unknown keys raise like the rest of `Config` (Q8).

## Open questions

1. ~~Plan 008 must be merged first~~ Settled: 009 is stacked on #23 (plan 008) and consumes its dependents index; `depends_on` now reads `"008.00"`. Decided 2026-10-15 by the owner (Konstantin): stack it on #23.
1. How does `resync dirs` treat a 💣 folder whose answer arrives and whose prior path is unknown? Assumed: the unblocker returns it to ⭕️ or 🅱️ by `blocked.md` content, then the normal path resumes. Not anchored; confirm in planning.
1. Does answering via Respond re-start the 7-day clock if the answer is incomplete and lando re-blocks? Assumed yes, because a new `blocked` signature is written.
1. Which existing `hold` Pause reuses: all agents or only the 💣 plan's (research Q7)? N10 says "every agent"; assumed all.
1. Should a deferred-by-aging plan carry a marker so it is not mistaken for a human defer? Not in the decision doc.
1. Does the exit-code on 💣 apply when `--ignore-bombs` lifts the halt but a 💣 still exists? Assumed 0.
1. Does the 7-day limit use calendar days or 24 h multiples across DST? Assumed 24 h multiples.

## Risks to planning or execution

- Plan 008 is unbuilt (`008.00-…/spec.md`), so 009 cannot be built or fully tested until it merges.
- Touches `status.rb`, `state_machine.rb`, `mapping.rb` and `commands.rb`, all likely to collide with other open plans; build in its own worktree.
- Tests must backdate `state.json` signatures, not stub the clock inside the sweep, or the filesystem fixture stops being honest.
- The halt rewrites a fixed-point rule in `Dispatcher#done?` (`dispatcher.rb:185`); a mistake could stall a run silently.
- The front end has no Pause, Discuss or Respond today (`UnblockWidget.tsx`, `AskCard.tsx`, `Copilot.tsx` draft-only), so the pair must agree on payloads early.

## Conclusion

When this ships, a plan blocked for 7 days with dependents becomes 💣, new work stops, and `openlanes run` exits 1 naming it. A blocked plan nobody needs moves itself to `deferred/` after 14 days with a trigger recorded. The control room shows each 💣 as a notice with Respond, Pause and Discuss and a 24 h override, and `--ignore-bombs` covers headless runs. `aging_since` in `.openlanes.yml` keeps paused weeks from counting.


## Research

Sources: repository code and the decision doc `docs/decisions/decisions-on-plan-folder-naming.md` (N2, N6, N8–N10). No web sources were used; none were needed. Code paths are relative to the worktree `openlanes.worktrees/009.00-plan-aging-and-bombs`. Read on 2026-10-13.

### Answers to the three questions

**1. The 💣 state.** Does not exist in code. Every layer needs adding:

- Status: `lib/openlanes/plans/status.rb:25` (`Status`), `:288-303` (blocked states, `open_block`), `:304-314` (deferred). Add a `:bomb` entry with `requires: %w[blocked.md]` and an invariant. Note `Status#violation` (`:32-36`) only sees a `Subject`.
- Event: `lib/openlanes/plans/state_machine.rb:205-215` holds the block and defer events. A new `bomb` event goes from `blocked` and `product_blocked` (the `BLOCKABLE` set at `:119`). Decide whether it sits in `FAMILIES` (`:93-96`) or `SETTLED` (`:111`).
- Linear: `lib/openlanes/linear/mapping.rb:41-61` (`PLACEMENTS`) and `:74-79` (`UNPLACED`). The spec `spec/openlanes/linear/mapping_spec.rb:10-14` fails until 💣 is in one of them.
- Emoji: U+1F4A3 is a single code point with emoji presentation, so it meets N2. No collision in `STATUSES`.

**2. `plans.aging_since` and the clock.** Does not exist. `lib/openlanes/support/config.rb:84` (`KEYS`) is `project lane frontend jobs redis_url commands`. Unknown keys raise at `:125-129`, so `.openlanes.yml` fails today if it carries `plans:`. The key must be added to `KEYS` and parsed as a date.

The clock start must come from a real timestamp. Options in code:

- `state.json` `blocked` signature `at`, read at `lib/openlanes/plans/plan_state.rb:163-172`. The snapshot already uses it (`web/live/snapshot.rb:279-280`), falling back to `blocked.md` mtime.
- Git rename date, which N8 names. Nothing in `lib` reads git dates. `plans_on_ref` uses `ls-tree` (`lib/openlanes.rb:128-136`).

Answers are dated by day only (`live/commands.rb:231-233`), so they cannot be the start.

**3. How `run` halts, and the lifts.** Nothing halts on blocks today:

- `Engine::Runner#blocked` (`lib/openlanes/engine/runner.rb:168`) reports blocked plans and does not stop the run.
- `Engine::Dispatcher#done?` (`lib/openlanes/engine/dispatcher.rb:185`) ends at a fixed point. `#next_dispatchable` (`:703`) skips `SETTLED` (`:716`).
- `lib/openlanes/cli/run/run.rb:219` exits 1 only when an attempt failed. A blocked plan gives exit 0. "Exits non-zero naming it" needs a new exit path.
- `--ignore-bombs`, "Resume anyway" and any expiry time: no matches in `lib`, `exe`, `web/src` or `spec`. The only `--ignore-*` flag is `--ignore-user-config` (`lib/openlanes/adapters/codex.rb:20`).

### Notice and answers

- Respond exists in parts: the question card `web/src/panels/AskCard.tsx` (answer box, "Send answer") and `web/src/panels/question.ts` (`answer`, `choose`). The widget is `web/src/panels/UnblockWidget.tsx`.
- Pause and Discuss do not exist. Closest: agent `hold` (`lib/openlanes/live/commands.rb:40`, `lib/openlanes/execution/control.rb:31-38`) and per-question `hold_blocked` and `release_hold` (`commands.rb:241-251`).
- Copilot `web/src/copilot/Copilot.tsx:52-69` drafts into the box and never sends.
- Command kinds are in `commands.rb:33-44`. None is Respond, Pause or Discuss.
- Respond writing into `blocked.md` is a new command. Folding is already done by `lifecycle/unblocker.rb` (`:147`, `:177`) through `lando-broker`.

### Contradictions

Production is what the code runs today.

1. **Dependents index.** N6 and N8 need `Plans::Tree` to compute dependents. Plan 008 is ⚪️ New and unbuilt. Nothing in `lib` reads `depends_on`. Production: no index, so 💣 has no data.
2. **Invariant cannot see dependents.** `Subject` (`plans/subject.rb:12`) has no `Tree` reference. Production: a 💣 invariant of "has dependents" cannot be written in `Status` as it stands.
3. **Clock source.** N8 (`decisions…md:88`) says git rename date. Production: `state.json` signature `at` (`plan_state.rb:163-172`). Production runs the second.
4. **Auto-deferral trigger.** N8 moves blocked plans to `deferred/`. Production `:deferred` requires `delayed.md` naming a trigger (`status.rb:304-314`). N8 does not say who writes it.
5. **Time-based invariant.** `CLAUDE.md` says `resync dirs` asks each invariant of the folder's state, and "asking a question about a folder must never fire one". A 💣 invariant that depends on the wall clock would flip folders as days pass with no event.
6. **Exit code.** N9 (`:94`) says `lanes run` exits non-zero. Production: exit 1 only on failed attempts (`run.rb:219`).
7. **Emoji.** N2 (`:17-22`) replaces ⭕️ 🅱️ ☢️ with ⭕ 🛑 💤. Production uses the old forms (`status.rb:290`, `:298`, `:306`). Production runs the old form, and N2 is not built.
8. **`depends_on` form.** This plan says `depends_on: ["008"]` (`spec.md:2`). Plan 008 (`008.00-…/spec.md:71`) says entries must be canonical `"008.00"`. Production `Spec` ignores the key (`plans/spec.rb:134-148`, per 008's spec `:99`).
9. **Spec drift.** This `spec.md` has a second, empty `## What we are trying to achieve` through `## What research needs to settle` block (old lines 34-43), after the real chapter. It should be removed by yoda-writer or a human.

### Open questions

1. Is the clock start `state.json` `blocked` `at`, or the git date N8 names? Recommendation: `state.json`. It is written at the moment of blocking and needs no git history.
2. Who writes `delayed.md` with a trigger when a plan auto-defers? N8 is silent. Recommendation: the aging step writes it with the trigger "revisit after answer", so the invariant holds.
3. Is 💣 a folder state set by `resync dirs` through its invariant, or by an explicit aging sweep that fires an event? Recommendation: an explicit sweep event, so the invariant stays pure and asking never fires.
4. Does plan 008 land before 009? 009 cannot be built without the dependents index.
5. What exit code does `lanes run` give when 💣 exists, and does `lanes start` idle?
6. "Resume anyway for 24 h": stored where, and with what expiry field? Recommendation: `state.json`, timestamped, so it expires without a config edit.
7. Pause and Discuss need new command kinds in `commands.rb:33-44`. Which existing `hold` does Pause reuse, and does Discuss open the copilot with `plan` preloaded?
8. Is the `plans:` config block in `.openlanes.yml` validated as a whole, or key by key?

### Findings, Conclusion & References

- 💣 is new across status, event, Linear, and the emoji spec. Nothing exists yet.
- `aging_since` is new config. It needs a `KEYS` entry.
- Halting is new work. Today a block only reports, and `run` exits 0.
- Pause, Discuss and Respond-into-`blocked.md` are new commands.
- The dependents index depends on unbuilt plan 008. This is the blocking dependency.
- Auto-deferral has no defined trigger, and a wall-clock invariant conflicts with the rule that asking never fires.

Conclusion: the feature can be specified, but the spec must settle open questions 1–4 before implementation. Items 4 and 5 may need a human; the others are for yoda-writer to decide and record.

References (repository, no external sources):

- `docs/decisions/decisions-on-plan-folder-naming.md` N2, N6, N8, N9, N10
- `CLAUDE.md` (worktree root): "The folder name is the state", "Firing an event is a real side effect"
- `.plans/008.00-⚪️ → plan-dependencies/spec.md` lines 71, 99
