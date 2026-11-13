# Contract: 062.00 Make Openlanes Cheaper

Owner: backend-coder. Partner: frontend-coder (F1).

## Baseline

Full suite (`bundle exec rspec`) before any change: see "Baseline result" below, filled in when the run finishes.

## Interfaces frontend-coder calls

### Snapshot `plans[].spend` (B5)

No new route. Every entry of `Snapshot.plans` (the live snapshot JSON, `web/src/api/types.ts` `Plan`) gains one key:

```
spend: {
  usd:           number,        // estimated dollars spent on this plan, summed from priced runs; 0 when none
  cap:           number | null, // .openlanes.yml budget.plan_usd; null when unset (no cap)
  over:          boolean,       // true when cap is set and usd >= cap; always false with no cap
  unpriced_runs: number         // runs whose cost is unknown (codex, pi, ...); never folded into usd
}
```

- Always present on every plan row; never null itself.
- `usd` rounded to 4 decimals.
- Errors: none. A missing or unreadable event log yields `{ usd: 0, cap: <cap>, over: false, unpriced_runs: 0 }`.
- The hold reason for an over-cap plan, where the board shows one, reads `over budget: $X of $Y` (X and Y to 2 decimals).

Display (F1, frontend-coder): `$1.84 / $5.00` with a meter; over cap gets the over-budget style; no cap shows `$1.84` alone; `unpriced_runs > 0` shows `+N unpriced`. Dollars are estimates: label "est.".

## File ownership

| Files | Owner |
| --- | --- |
| `lib/**`, `spec/**`, `agents/deploy-assessor.md`, `schemas/**` | backend-coder |
| `web/src/board/{model.ts,Car.tsx,format.ts,board.css,model.test.ts,Car.test.tsx}` | frontend-coder |
| `web/src/api/types.ts` (`Plan.spend` type) | frontend-coder writes it; backend-coder's `snapshot_spec.rb` checks keys against the web fixture |
| `web/src/board/sample.ts` / snapshot fixture used by `snapshot_spec.rb` | frontend-coder adds `spend` to the fixture first; mail backend-coder when done |

## Build order

B1, B2, B3 independent. B4 after B3. B5 after B3 and B4. F1 after B5's shape, which is fixed here, so F1 may start now.

## Integration proof

`spec/openlanes/integration/plan_budget_spec.rb`: real `.plans` tree (`PlansFixture`), real event log with priced `agent_finished` usage for one plan past `budget.plan_usd`, dispatcher assign step with a stub executor, then the live snapshot through `Web::App` via `Rack::Test`, asserting `spend` on both plans and the over-cap plan held.

## Assumptions

- A1: spend source is the durable event log (`Events.log(Events.dir(root:)).events`, kind `agent_finished`, payload `cost_usd`). When `events.enabled` is off there is no log, so spend reads 0 and no cap is enforced. Mailed to frontend-coder.
- A2: `PlanSpend.for(ordinal, events, cap: nil)` takes the cap as a keyword; `Engine::Budget` is the dispatcher's and the snapshot's one seam onto it (cap via `PlanSpend.cap_for(Config.current)`, events from the log, re-read at most every 5 s).
- A3: `fixture` amended: `web/src/api/fixtures/snapshot.json` gained `spend` on every plan (written by backend-coder after F1 finished, so `snapshot_spec.rb`'s key check passes). Mailed.

## Built (matches the code)

- `Events::PlanSpend` (`lib/openlanes/events/plan_spend.rb`): `usd`, `unpriced_runs`, `cap`, `over?`, `share`, `reason`, `wire`.
- `Config#budget_plan_usd`, `.openlanes.yml` `budget: { plan_usd: <positive number> }`; 0, words, unknown keys refused.
- `Engine::Budget` (`lib/openlanes/engine/budget.rb`), injected into `Dispatcher.new(budget:)` and `Live::Snapshot.new(budget:)`; `Live::Publisher` builds `Budget.local`.
- Dispatcher: an over-cap plan is skipped at assignment, logged once, and named in the idle reason as `held by budget: NNN over budget: $X of $Y`.
- B1: `Prompt.new(resumed:)`; a resumed session gets only rounds > round-1 plus "This session already holds N earlier journal entries".
- B2: `small_diff:` frontmatter (`Agents::SmallDiff`), `Profile.resolve(diff_lines:)`, `Vcs::DiffSize.lines`.

## Known gaps

- The CLI board text (`$1.84 / $5.00`) is not built; the web board (F1) carries the display.
- A plan held by budget before any agent ran this session is not on `Engine::Board#plans`, so the page only shows its spend once it is on the board or claimed. The integration spec names both plans on the board.

## Baseline result

8 failures on clean HEAD, all fixed in this plan (see `pull-requests.md`). Final full suite: 0 failures besides one inventory row added afterwards and re-run green.
