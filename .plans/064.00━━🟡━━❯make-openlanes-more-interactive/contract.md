# Contract: 064.00 Make OpenLanes more interactive

Owner: backend-coder. Wire shapes frontend-coder builds against. `openapi.yaml` (B3) will sit beside this file once `GET /api/plans/:ordinal/review` lands.

## Baseline

The clean baseline run was killed at its time limit, so failures were attributed by file: after B1, B2 and B4, `bundle exec rspec` gives 2288 examples, 6 failures, 5 pending.

- Not from this plan (no file under them was touched): `spec/openlanes/agents/routing_spec.rb:19`, `:32`, `:42` (frontend-coder routed where the spec expects backend-coder only), and `spec/openlanes/live/redis_outage_integration_spec.rb:72`, `:100` (real Redis; flaky between runs, 1 or 2 failures).
- From this plan, fixed: `spec/openlanes/docs/architecture_doc_spec.rb:13` (new `Live::BoardDelta`), by `just update-architecture`.

## Findings in the existing code

- **wrap_up**: `WRAP_UP` in the control file tells the agent to finish the step it is in, write to disk and sign its ledger entry, which is what "stop after this step" means, so the drawer's button sends the existing `wrap_up` kind and there is no `stop_after_step` kind.

## 1. Event stream: `board` and `board_delta` frames (B1)

- On connect (and on every reconnect, whatever `Last-Event-ID` says) the stream sends one full frame:
  - `event: board`, `data: { me: Snapshot|null, others: Snapshot[], version: Integer }`.
  - `version` is per stream, starting at 1. It is not stored anywhere; a new connection starts again at 1.
- After that, while the board changes, the stream sends:
  - `event: board_delta`, `data: { base: Integer, version: Integer, upsert: Entry[], remove: String[] }`
  - `Entry = { key: String, value: Object }`.
  - `base` is the `version` the delta applies onto; `version = base + 1`.
- Keys flatten the board:
  - `"node/<node.id>/<node.checkout>"` → the snapshot with `plans` removed and `plan_order: String[]` (the ordinals, in the snapshot's order) added. `value.node.me` says whether it is `me` or one of `others`; `others` stay sorted by `node.host`.
  - `"plan/<node.id>/<node.checkout>/<ordinal>"` → one `Plan` hash, exactly as it sits in `snapshot.plans`.
- amended: the stream's version and last-sent board live in `Live::BoardDelta::Stream`, one per connection; the wire shape is unchanged.
- Apply: replace each upserted key, delete each removed key, rebuild each snapshot's `plans` from its `plan_order`. A removed node key removes its plans too (they are listed in `remove` as well).
- A delta whose `base` is not the cached `version` must not be applied: the page reconnects (or refetches), which yields a fresh full `board`.
- When a delta's JSON would not be smaller than the full board's, the stream sends a full `board` frame (with the next `version`) instead.
- Errors: none on the wire; a stream that cannot reach the store ends as today.

## 2. Command `extend_time` (B2)

- `POST` to the existing command endpoint, `kind: "extend_time"`, `plan` and `agent` required, `payload: { seconds: Integer }`.
- `seconds` must be a whole number from 1 to 1200 (`Engine::Extensions::CHOICES`' largest grant, 20 minutes). The drawer sends 600 or 1200.
- Shape errors (missing plan, agent or seconds) are a 422 from `Command.parse`, as for every kind.
- Replies (by the `reply` frame):
  - `done`, reason `"<agent> has <N> more minutes"`; the car's clock deadline moved and its control file says `WARN: <m> minutes left, time was extended`. The car's `remaining` grows on the next board.
  - `refused`, reason `"<plan>/<agent> is not running"` when no such car runs, or `"seconds must be a whole number from 1 to 1200, not <x>"`.
- Stop after this step: send `wrap_up` (existing kind), see Findings.

## 3. Review: diff and findings (B3) — NOT BUILT YET, shape is the plan's proposal

- `GET /api/plans/:ordinal/review` → `200 { diff: { stat: String, patch: String, truncated: Boolean }, findings: Finding[] }`
- `Finding = { id: "F<n>", reviewer: String, severity: String|null, file: String|null, line: Integer|null, text: String, ruling: "accept"|"strike"|null }`
- `404 { error }` for an unknown plan.
- Command `rule_finding`: `plan` required, `payload: { finding: "F<n>", verdict: "accept"|"strike" }`. Reply `done` with reason `"F<n> <verdict>"`, or `refused` naming an unknown finding or verdict.
- A ruling is recorded in `state.json` `rulings` with `kind: "finding"`, `by: <person>`, so the next `GET` returns it with `ruling` set.

## 4. Car cost (B4)

- Built in `Live::Snapshot#car`, not on `Engine::Board::Row`: the snapshot already holds the adapter price lookup the plan's cost uses, so `Row` stays unpriced (one place prices).
- The demo board (`openlanes web --demo`) charges 3/15 dollars per million tokens and adds each tick's spend to both the car and its plan; its fixture's plan `cost` values are not the sum of their cars', so the F4 check should compare the increments or the engine's board.
- Every `Car` in a snapshot gains `cost: Number` (USD, rounded to 4 places), priced from the car's model and its `up`/`down` tokens with the same rates the plan's `cost` uses. 0 when the model has no price.
- A plan's `cost` stays the `Meter` total: every row it has seen, including those that have left the board, so it is at least the sum of its cars' costs and equals it while every row is still on the board.

## File ownership

- Backend (backend-coder): everything under `lib/` and `spec/`, `contract.md`, `openapi.yaml`.
- Frontend (frontend-coder): everything under `web/`.
- Shared: none. `web/src/api/types.ts` is frontend-coder's alone (F1).

## Build order

B2 → B3; B1, B4 independent. F1 needs this file only, not the code. F2 needs B2, F3 needs B3, F4 needs B1 and B4.

## Integration proof

`web/cypress/e2e/interactive.cy.ts` (F4) against the real `openlanes web` server on its demo board, nothing stubbed: board_delta frames after one board, extend_time reply and `remaining` growth, strike persisted across a reload, plan cost equal to its cars' sum.
