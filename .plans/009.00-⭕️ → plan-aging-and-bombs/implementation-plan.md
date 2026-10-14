# Plan 009.00 — implementation plan (contract)

Owner: `luke-backend`. Partner: `rey-frontend`.

## Baseline

`bundle exec rspec` before any change: 2214 examples, 0 failures. `bundle exec rubocop`: 0 offenses.
After B1 + B2: 2229 examples, 0 failures; rubocop 0 offenses.

## Status

| Unit | State |
| --- | --- |
| B1 💣 state, `bomb` event, Linear mapping | done |
| B2 `plans.aging_since` | done |
| B3–B7 | blocked: plan 008 (dependents index) is ⭕️ and unbuilt; see `blocked.md` B1 |

## Interfaces rey calls

Sent through the existing command channel (`live/commands.rb`):

- `{ "kind": "respond", "plan": "009.00", "text": "..." }` — appends the answer under the open question in `blocked.md`. Errors: plan unknown; plan not 💣; text blank.
- `{ "kind": "pause_discuss", "plan": "009.00" }` — holds every running agent via `Execution::Control` `hold`. No file change. Errors: plan unknown; plan not 💣.
- `{ "kind": "resume_anyway", "plan": "009.00" }` — `PlanState#resume_anyway!(until: now + 24 h)`. Errors: plan unknown; plan not 💣.

Snapshot field (`live/snapshot.rb`), always present, `[]` when there are none:

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

- luke: `lib/**`, `spec/**`, `schemas/**`, `docs/WORKFLOW.md` (regenerated).
- rey: `web/src/**` per `plan-frontend.md`. Shared: the snapshot type in `web/src` — rey writes it, against the field above.

## Build order

B1, B2 → B3 (needs plan 008) → B4 → B5, B6 → B7. F1 against this contract any time.

## Integration proof (B7)

`spec/openlanes/web/bombs_integration_spec.rb`: real `.plans` tree, real web server, only the agent process and the `GitHub` seam stubbed; as listed in `plan-backend.md` B7.
