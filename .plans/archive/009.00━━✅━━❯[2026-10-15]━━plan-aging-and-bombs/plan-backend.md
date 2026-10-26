# Plan 009.00 — back end

`backend-coder` builds these, in the order B1 → B7. B1 and B2 can run at the same time. See `plan.md` for the graph and the shared contract.

Prerequisite: stacked on #23 (plan 008, the dependents index). B3 consumes it and is the only unit that does.

## B1 State, event and Linear mapping

- **Discipline:** back end
- **Owns:** `lib/openlanes/plans/status.rb`, `lib/openlanes/plans/state_machine.rb`, `lib/openlanes/linear/mapping.rb`, `agents/unblocker.md` (`handles:`), their specs (`spec/openlanes/plans/status_spec.rb`, `spec/openlanes/plans/state_machine_spec.rb`, `spec/openlanes/linear/mapping_spec.rb`, `spec/openlanes/lifecycle/unblocker_spec.rb`), and whatever `openlanes docs` regenerates.
- **Must not touch:** `support/config.rb`, `engine/*`, `live/*`, `cli/run/*`, `web/src/*`.
- **Depends on:** nothing
- **Builds:**
  - `:bomb` in `STATUSES`: emoji 💣 (U+1F4A3), `requires: %w[blocked.md]`, invariant "blocked.md present" and nothing time-based.
  - `bomb` event: `blocked` → `bomb`, `product_blocked` → `bomb`. Placed with the blocked family, not `SPINE`. `bomb` is skipped by `next_dispatchable` like the other `SETTLED` blocks.
  - Exit from `bomb`: amended (plan.md, decision 1): the unblocker is unchanged; it gates on `blocked.md`, so a 💣 drains like ⭕️. 💣 leaves by every event a block leaves by, and `block` / `block_on_product` accept it. `unblocker` handles 💣 so the run loop can drain it.
  - `defer` event accepts `blocked` and `product_blocked` as sources if it does not already.
  - 💣 placed in `PLACEMENTS` (same Linear state as the other blocks).
- **Done when:** `state_machine_spec.rb` covers `bomb` in from both blocked states and out via unblock; `status_spec.rb` covers the invariant; `mapping_spec.rb` green; `unblocker_spec.rb` folds an answer out of a 💣 folder; `openlanes states` lists 💣 and `openlanes docs` regenerates cleanly.

## B2 Config key `plans.aging_since`

- **Discipline:** back end
- **Owns:** `lib/openlanes/support/config.rb`, `spec/openlanes/config_spec.rb`.
- **Must not touch:** anything B1 owns.
- **Depends on:** nothing
- **Builds:** `plans` added to `Config::KEYS`; `plans:` is a hash validated key by key; only `aging_since` is known, parsed as a `Date`. A malformed date or an unknown key under `plans:` raises naming the key (`plans.aging_since`, `plans.<unknown>`). Absent means no floor. Reader: `Config#aging_since` → `Date` or `nil`.
- **Done when:** `config_spec.rb` covers valid date, absent, malformed date, and unknown key under `plans:`.

## B3 Aging sweep and auto-defer

- **Discipline:** back end
- **Owns:** `lib/openlanes/lifecycle/aging.rb` (new), `lib/openlanes/lifecycle.rb` (facade method only), `spec/openlanes/lifecycle/aging_spec.rb` (new).
- **Must not touch:** `status.rb`, `state_machine.rb`, `config.rb`, `engine/*`.
- **Depends on:** B1, B2, #23 (`Tree#blocks_of`).
- **Builds:**
  - `Lifecycle::Aging` with constants `BOMB_AFTER = 7 * 86_400` and `DEFER_AFTER = 14 * 86_400` (24 h multiples, not calendar days). This is the one place the limits live.
  - `Aging#age_of(subject, now:, since:)` → seconds. Clock start is the later of the latest `blocked` signature `at` in `state.json` (fallback: `blocked.md` mtime, as `live/snapshot.rb` does) and `aging_since`.
  - `Aging#call(tree, now:, since:, dry_run: false)` → `Data` result listing `bombed` and `deferred` plans. Blocked (⭕️/🅱️) plan with dependents past `BOMB_AFTER` fires `bomb`; blocked plan with no dependents past `DEFER_AFTER` fires `defer`, writing `delayed.md` first with trigger "revisit after the block is answered" and a line marking it as deferred by aging (spec open question 5: mark it).
  - Only ⭕️ and 🅱️ age. 💣 never defers.
  - Dependents: `tree.blocks_of(ordinal)`, open ones only (plan.md, decision 9).
  - Facade: `Lifecycle.age(tree, now:, since:)`.
- **Done when:** `aging_spec.rb`, using `PlansFixture` trees with backdated `state.json` signatures (no clock stubbing inside the sweep), shows: `aging_since` today → nothing ages; backdated 8 days with a dependent → 💣; 15 days without dependents → `deferred/` with `delayed.md` and the `:deferred` invariant holding; 💣 and non-blocked states untouched; a fresh `blocked` signature restarts the clock.

## B4 Engine halt and resume-anyway expiry

- **Discipline:** back end
- **Owns:** `lib/openlanes/engine/runner.rb`, `lib/openlanes/engine/dispatcher.rb`, `lib/openlanes/plans/plan_state.rb`, `schemas/plan-state.schema.json`, `spec/openlanes/engine/runner_spec.rb`, `spec/openlanes/engine/dispatcher_spec.rb`, `spec/openlanes/plans/plan_state_spec.rb`.
- **Must not touch:** `cli/run/*`, `live/*`, `lifecycle/aging.rb`.
- **Depends on:** B3.
- **Builds:**
  - `Runner` calls `Lifecycle.age` once per round, before assignment (after the first `resync dirs`). `Runner` gains `ignore_bombs:` (default `false`).
  - `PlanState#resume_until` / `#resume_anyway!(until:)`: a timestamped expiry in `state.json`, added to the schema.
  - `Dispatcher::BLOCKED` gains `:bomb`, so an answered 💣 is drained in the loop like an answered ⭕️.
  - Halt: while any 💣 exists whose `resume_until` is absent or past, and `ignore_bombs` is false, `Dispatcher` assigns nothing new; running agents finish. `Dispatcher#done?` treats "halted with nothing running" as the end, not as a stall.
  - `Runner#bombs` → the 💣 plans that halted the run, for the CLI to report.
- **Done when:** `runner_spec.rb` with a backdated tree shows the sweep bombs a plan, nothing new is assigned, the run ends; with `ignore_bombs: true` work proceeds; with `resume_until` in the future work proceeds, and in the past it halts. `dispatcher_spec.rb` shows a running agent is joined, not killed, when the halt starts.

## B5 `run` exit code, `--ignore-bombs`, `start` idles

- **Discipline:** back end
- **Owns:** `lib/openlanes/cli/run/run.rb`, `lib/openlanes/cli/start/*`, their specs under `spec/openlanes/cli/`.
- **Must not touch:** `engine/*`, `live/*`.
- **Depends on:** B4 (same halt API; sequential).
- **Builds:** `--ignore-bombs` flag passed to `Runner`. `openlanes run` exits 1 when `Runner#bombs` is non-empty and the halt was not lifted, naming each 💣 plan on STDERR. With `--ignore-bombs`, exit code follows the existing rule (0 unless an attempt failed; spec open question 6). `lanes start` keeps serving and idles while halted.
- **Done when:** CLI spec shows exit 1 with the plan named on STDERR, exit 0 with `--ignore-bombs`, and `start` not exiting on a halt.

## B6 Command kinds and snapshot field

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/commands.rb`, `lib/openlanes/live/snapshot.rb`, `spec/openlanes/live/commands_spec.rb`, `spec/openlanes/live/snapshot_spec.rb`.
- **Must not touch:** `engine/*`, `plan_state.rb`, `web/src/*`.
- **Depends on:** B1, B4 (`PlanState#resume_anyway!`).
- **Builds:** three `HANDLERS` entries, payloads as in `plan.md` → Contract:
  - `respond` (plan, text): appends the answer under the open question in the plan's `blocked.md`, in the form the unblocker already folds. No state change here.
  - `pause_discuss` (plan): signals `hold` to every running agent through the existing `Execution::Control` path. No file changes.
  - `resume_anyway` (plan): `PlanState#resume_anyway!(until: now + 24 h)`.
  - Snapshot gains `bombs`: one entry per 💣 with `plan`, `slug`, `blocked_md` (raw markdown), `blocked_since` (ISO 8601), `resume_until` (ISO 8601 or null).
- **Done when:** `commands_spec.rb` covers each kind (file written, holds signalled, expiry written, refusal on a non-💣 plan); `snapshot_spec.rb` covers the `bombs` field.

## B7 Integration check

- **Discipline:** back end
- **Owns:** `spec/openlanes/integration/plan_aging_spec.rb` (new; amended from `spec/openlanes/web/bombs_integration_spec.rb` to sit beside 008's integration spec).
- **Must not touch:** everything else.
- **Depends on:** B5, B6.
- **Builds:** one spec, nothing stubbed but the agent process and the `GitHub` seam. A real `.plans` tree with one ⭕️ plan that another plan depends on, its `blocked` signature backdated 8 days.
- **Must show:**
  1. `openlanes run` exits 1 and names the plan; the folder is now 💣.
  2. The web server's snapshot endpoint returns that plan in `bombs` with its `blocked.md` text.
  3. POSTing `respond` through the server's command endpoint writes the answer into `blocked.md`.
  4. The next round's unblocker folds it; the plan leaves 💣 and disappears from `bombs`; the halt is gone.
  5. POSTing `resume_anyway` on a second 💣 lifts the halt without any config edit.
- **Done when:** `spec/openlanes/integration/plan_aging_spec.rb` green, and `bundle exec rspec` and `just lint` green.
