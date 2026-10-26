# Plan 009.00 — implementation plan (contract)

Owner: `backend-coder`. Partner: `frontend-coder`.

## Baseline

`bundle exec rspec` before any change: 2214 examples, 0 failures. `bundle exec rubocop`: 0 offenses.
After B1 + B2: 2229 examples, 0 failures; rubocop 0 offenses.
Rebased onto #23 (2026-10-15), B1 + B2 included: 2269 examples, 0 failures.

## Status

| Unit | State |
| --- | --- |
| B1 💣 state, `bomb` event, Linear mapping | done |
| B2 `plans.aging_since` | done |
| B3 aging sweep, auto-defer | done: `lib/openlanes/lifecycle/aging.rb` |
| B4 engine halt, `resume_until` | done |
| B5 `run` exit 1, `--ignore-bombs`, `start` idles | done |
| B6 three command kinds, `snapshot.bombs` | done |
| B7 integration check | done: `spec/openlanes/integration/plan_aging_spec.rb` |
| F1 bomb notice (frontend-coder) | done: `web/src/panels/BombNotice.tsx` |

## Interfaces frontend-coder calls

Sent through the existing command channel (`live/commands.rb`):

- `{ "kind": "respond", "plan": "009.00", "payload": { "text": "..." } }` — appends the answer under the open question in `blocked.md`. Errors: plan unknown; plan not 💣; text blank.
  - amended: like every command, the fields beyond `kind`, `plan` and `agent` travel in `payload` (`Command` in `web/src/api/types.ts`). `respond` answers the first open question with no answer yet, as `## A<n>`, exactly as `answer` does; refused when every question already has one.
- `{ "kind": "pause_discuss", "plan": "009.00" }` — holds every running agent via `Execution::Control` `hold`. No file change. Errors: plan unknown; plan not 💣.
- `{ "kind": "resume_anyway", "plan": "009.00" }` — `PlanState#resume_anyway!(until: now + 24 h)`. Errors: plan unknown; plan not 💣.

Snapshot field (`live/snapshot.rb`), top level of `Snapshot`, always present, `[]` when there are none. Lists every 💣 in this node's tree, on the board or not:

```json
"bombs": [
  { "plan": "009.00", "slug": "plan-aging-and-bombs",
    "blocked_md": "## B1 ...", "blocked_since": "2026-10-01T12:00:00Z",
    "resume_until": null }
]
```

`blocked_since`: ISO 8601 UTC. `resume_until`: ISO 8601 UTC or `null`.

## Built so far (real shapes)

- `Plans::STATUSES` gains `:bomb`, emoji 💣 (U+1F4A3), label "Bomb", `requires: %w[blocked.md]`.
  - amended: the invariant is `open_block("Bomb")` (an open `## B<n>` question), not merely "blocked.md present". With presence only, `resync dirs` moved a drained ⭕️ sideways into 💣 (the family's other member fit), failing `resync/dirs_spec.rb:226`. Still nothing time-based.
- `StateMachine`: event `bomb` from `blocked`, `product_blocked`. 💣 leaves via `block` / `block_on_product` (back to ⭕️/🅱️) and via every event a block already leaves by (`specify`, `research`, `ready_to_plan`, `plan`, `build`). 💣 does not defer. In `FAMILIES.first` (last, strongest claim), in `SETTLED`, in `PREFERENCE` after 🅱️.
- `Linear::PLACEMENTS[:bomb]`: Todo, labels `blocked`, `bomb`.
- `Config#aging_since` → `Date` or `nil`. `.openlanes.yml` `plans:` validated key by key; known: `aging_since`. Errors name `plans.aging_since` / `plans.<key>`.
- Unblocker: unchanged. It gates on `blocked.md`, not the emoji, so a 💣 folder already drains like ⭕️.

## File ownership

- backend-coder: `lib/**`, `spec/**`, `schemas/**`, `docs/WORKFLOW.md` (regenerated).
- frontend-coder: `web/src/**` per `plan-frontend.md`. Shared: the snapshot type in `web/src` — frontend-coder writes it, against the field above.

## Build order

B1, B2 → B3 (needs plan 008) → B4 → B5, B6 → B7. F1 against this contract any time.

## Built in B3–B6 (real shapes)

- `Lifecycle::Aging.new(tree:, since:, now:)`: `#call(subjects:, commit:)` → `Result(bombed:, deferred:)`, ordinals; `#started_at(subject)`, `#age_of(subject)`. Facade `Lifecycle.age(tree:, subjects:, since:, now:, commit:)`.
- `Runner.new(..., ignore_bombs: false, aging_since: nil)`; `#age!(except:)`, `#bombs`, `#halted_by`, `#halted?`. `Dispatcher#reconcile` ages after the resync; `#next_dispatchable` returns nil while halted. `Dispatcher::BLOCKED` includes `:bomb`.
  - amended: the sweep runs whenever the dispatcher looks for work, which is whenever a slot is free, not once per round: the dispatcher has ticks, not rounds. It is idempotent and reads only blocked plans' `state.json`.
- `PlanState#resume_until`, `#resumed?(now:)`, `#resume_anyway!(till:)`; `resume_until` added to the schema.
- `openlanes run --ignore-bombs`; `run` reads `plans.aging_since` through `Config.current`.
- Commands: `respond` replies `done` with "answered B<n>"; `pause_discuss` replies "held N agents; discuss NNN in the copilot"; `resume_anyway` replies "NNN halts nothing until <ISO 8601 UTC>". Each refuses a plan that is not 💣 with "NNN is <status>, not a 💣".
- `snapshot.bombs`: every 💣 in the tree not held by another machine; `blocked_since` is the clock start without the `aging_since` floor.

## Integration proof (B7)

amended: `spec/openlanes/integration/plan_aging_spec.rb`, beside 008's, not under `spec/openlanes/web/`. Real `.plans` tree, the real `exe/openlanes`, the control-room Rack app taking `POST /api/commands`, and `Live::Commands` applying them. Only the agent process is stubbed (the drainer retires `blocked.md`); `claude`, `codex` and `pi` on PATH are scripts that fail if called. The snapshot is read from `Live::Snapshot` directly rather than through `GET /api/board`, which only relays what a publisher stored.
