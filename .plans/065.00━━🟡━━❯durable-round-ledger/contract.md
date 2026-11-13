# Contract: Durable Round Ledger (065.00)

Owner: backend-coder. Frontend-coder reads it; amendments are marked `amended:`.

## Baseline

- `bundle exec rspec`, run as round 1 began: 6194 examples, 5 failures, 9 pending.
  - `spec/openlanes/cli/engine_command_spec.rb:289`, `:317` and `spec/openlanes/cli/web_spec.rb:255`, `:277`: control-room login/listen checks, unrelated to this plan.
  - `spec/openlanes/docs/architecture_doc_spec.rb:13`: stale `docs/architecture`. Probably set off by `plans/rounds.rb` being added while that run was going; regenerated in round 2 with `just update-architecture`.

## Interfaces frontend-coder calls

No new route. The live snapshot (`GET` the page's existing snapshot endpoint, `Live::Snapshot#to_h`) changes:

1. **Top level, new key `paused_clis`** (B5): array, empty when nothing is paused.
   - each item: `{ "adapter": "claude", "reason": "OAuth session expired", "since": "2026-11-12T10:00:00Z" }`
   - `adapter`: one of `claude`, `codex`, `pi`, `grok`, `gemini`. `reason`: the adapter's own words. `since`: ISO 8601.
   - Assumption until B5 lands: always present, `[]` by default, never `null`.
2. **Each car (running agent): `round`** keeps its key and type (integer) but is now read from `Plans::Rounds#next` for the agent's visit, i.e. the same number the agent was told and signs. `rounds` stays the agent's budget (frontmatter `rounds:` plus extension grants for this visit).
3. **Request choices on a rounds request** (B3), `label` strings, letters unchanged:
   - `a) One more round` (seconds 0)
   - `b) One more round with 10 extra minutes` (seconds 600)
   - `c) One more round with 20 extra minutes` (seconds 1200)
   - The server keeps accepting the old labels (`Extend Rounds by 1`, `Extend Time by 10 minutes`, `Extend Time by 20 minutes`) as answers. The page renders whatever `label` the snapshot sends; do not hard-code them.
   - Time requests (amended: B3 landed, exact strings): `a) One more round, starting again from its resume note`, `b) 10 more minutes on this round`, `c) 20 more minutes on this round`.
   - Field reference: [openapi.yaml](openapi.yaml).

Errors: none new. A snapshot without `paused_clis` (an older server) must render as "nothing paused".

## File ownership

- backend-coder: everything under `lib/`, `spec/`, `schemas/`, `agents/*.md` (frontmatter `rounds:` only), `docs/WORKFLOW.md`, `docs/USAGE.md`, `openapi.yaml`, this file.
- frontend-coder: `web/src/panels/NeedsYou.tsx`, `AgentDrawer.tsx`, `PausedCliBanner.tsx` and their tests, `web/src/api/types.ts`, `web/cypress/e2e/round-ledger.cy.ts`.
- Shared: none. If `web/` fixtures need a server-side seed for the e2e (paused CLI), frontend-coder asks by mail and backend-coder writes the Ruby side.

## Build order

B1, B2, B3, B7 (independent) -> B4 (dispatcher reads Rounds) -> B5 (CLI pause, snapshot `paused_clis`) -> B6 (integration). F1 can start now against the shape above.

## Integration proof

`spec/openlanes/engine/restart_rounds_spec.rb` (B6): real `Runner` and `Dispatcher` over a `PlansFixture` tree, a scripted fake `claude` through the real `Executor`; asserts told round == signed round == snapshot `round`, and `paused_clis` after three auth failures. Then `cd web && npx vitest run && cd .. && bin/web-e2e` with `round-ledger.cy.ts`.

## Built so far

- B1 done: `lib/openlanes/plans/rounds.rb` (`Plans::Rounds.from(plan_state)`, `used`, `next`, `left`, `failed_starts`), `PlanState::FAILED_START = "Failed start"`, `stage!` records `visit` (moves at dispatch) when `from:` is given; schema accepts both.
- B7 done: `Executor::Result#tools`, `#failed_start?` (not ok, not killed, not throttled, `Executor.spent_nothing?`, the same test `lost_session` now calls), `#auth_failure?` against `Executor::AUTH_FAILURE`. One shared pattern in `executor.rb` rather than per-adapter constants: the adapters do not see the run's final note. Spec lives at `spec/openlanes/execution/executor/result_failed_start_spec.rb` (rubocop's `RSpec/SpecFilePathFormat` rejects the name plan.md gave).
- B3 done: `Extensions::CHOICES` keyed by limit, labels as above; each request records `moves` when asked, and `Extensions#rounds` counts round grants for the current visit only, read from `state.json` (`@since` removed). A grant asked before this change (no `moves`) counts until the plan moves. `Live::Commands` reads only the letter, so it needed no change.
- B2 done: every `agents/*.md` states `rounds:`, all 1 for now (today's behaviour); the plan's defaults (coders 3, planners/reviewers 2) land with B4, since they change 5 dispatcher_spec examples that count rounds. `openlanes docs` has a `## Rounds` table built from the registry; `docs/WORKFLOW.md` regenerated.
- B4 partly built (round 3): `Dispatcher::Desk#past_rounds` seeds the in-memory history from `Plans::Rounds` (current visit) the first time a process asks about an agent on a state, and `#next_round` never tells a number below `Rounds#next` as read at that moment. `Start` numbers rounds through `next_round`; `Assign#eligible?` and `#out_of_rounds` budget through `past_rounds`. Proof: `spec/openlanes/engine/dispatcher_rounds_spec.rb` (engine stopped after round 1, restarted, told 2 and 3; nothing handed out once every round was spent).
- B4 decision: the history stays as a per-process cache seeded from `state.json`, rather than going entirely, so the in-process handbacks (resume, requeue, block drained, lane re-added) keep working without a persisted `refunded` field; a handed-back round keeps its number, since it was never spent. The disk floor applies at seed time only for that reason. amended: replaces the `in`/`refunded` design above for now.
- Note for the failed-start stage: it must land together with the cap of 3, because the suite's fake executors return `ok: false` with no tokens, which `Result#failed_start?` classes as a failed start; without the cap they would never run out of rounds.
- Not yet built: B4's failed-start stage in `Settle` (no round spent, 3-strike cap), default rounds 3/2/1 in `agents/*.md`, B5 (CLI pause, `paused_clis` in the snapshot), B6 (`restart_rounds_spec.rb` with a fake CLI), `.openlanes.yml` coverage check.
- B4 design for next round: stages get `in` (the state the round worked in, after `starts_as`), `Rounds` matches `in`, then `from`, then `to`; the in-memory handbacks (resume, requeue, block drained, lane re-added) become a persisted `refunded: true` on the stage, which `used` skips but `next` still numbers past.
- Deviation from plan.md: the visit is stored as a new stage field `visit`, not in `moves`, because `moves` already means "moves when it settled" and `PlanState#resumption` depends on that.
