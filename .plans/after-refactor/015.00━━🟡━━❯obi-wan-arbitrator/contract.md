# Contract: 015.00 Obi Wan Arbitrator

Owner: backend-coder. frontend-coder amends an entry when the code disagrees and mails backend-coder.

## Baseline

`bundle exec rspec` on this worktree at `667bcf0e`, before any change: 4159 examples, 0 failures, 9 pending; exit 0. `bundle exec rubocop`: no offenses.

## Interfaces frontend-coder reads

No HTTP route is added or changed; no `openapi.yaml`. The live snapshot payload (`lib/openlanes/live/snapshot.rb`, `Snapshot#plan`) gains three keys on every plan object:

### `rejections`

```
rejections: { count: Integer >= 0, max: Integer >= 1 }
```

- `count`: staff-reviewer and verifier `rejected` signatures since the last `cap` ruling, fully struck rejections skipped (B3, `Arbitration::Counter`).
- `max`: `merge.max_rejections` from `.openlanes.yml` (`Config#max_rejections`).
- Always present. `count: 0` means render nothing.

### `ruling`

```
ruling: null | {
  at:       String (ISO 8601, UTC),
  kind:     "cap" | "appeal" | "dispute" | "passed_check",
  pr:       Integer | null,
  round:    Integer | null,
  outcome:  String,           # cap: go|no_go; appeal: upheld|struck; dispute: backend-coder|frontend-coder; passed_check: fair|too_harsh|too_lenient
  findings: { struck: [String], critical: [String] },
  winner:   String | null,    # dispute only
  reason:   String,
  trigger:  String            # appeal | dispute | cap | passed_check
}
```

The latest entry of `state.json`'s `rulings` array, or `null` when there is none.

### `arbitrating`

```
arbitrating: Boolean
```

`true` while an arbitrator stage is open for the plan (a `stages` entry whose `agent` is `arbitrator` and that has no `finished_at`), else `false`.

## File ownership

| Files | Writer |
| --- | --- |
| `lib/**`, `agents/**`, `schemas/**`, `evals/**`, `spec/**` | backend-coder |
| `web/src/api/types.ts`, `web/src/board/**` and their tests | frontend-coder |
| `contract.md` | backend-coder (frontend-coder amends, mails backend-coder) |

No shared file. `web/src/api/types.ts` is frontend-coder's alone; backend-coder never edits `web/**`.

## Build order

B1, B2 → B3, B4, B6 → B5, B7 → F1. F1 needs only the shapes above, so frontend-coder can start now against them.

## Integration proof

`spec/openlanes/engine/dispatcher_arbitration_spec.rb` (B5): real ticks over a `PlansFixture` tree with the fake `gh` and a fake adapter whose final text is a ruling block; then `Live::Snapshot#to_h` for that plan carries the ruling and `rejections: {count, max}`. The front end's half of the proof is frontend-coder's Vitest spec over a payload of exactly these shapes.

## Back-end progress

- Round 1: B1 (agent, `Arbitration::Ruling`), B2 (`PlanState#rule!`, schema, `state show`), B3 (`Arbitration::Counter`), B4 (`Arbitration::Effects`), B6 prompt half, B7 (snapshot fields).
- Round 2: B5 — `Engine::Arbitration` (triggers in the spec's order, `#holds?`, `#tick`, `Asker` runs the agent through the executor and reads its answer from the trace), wired into `Runner`, `RunWorkflow#arbitration_for` and `Dispatcher#tick` / `#eligible?`; `Verification::Outcome` blocks the plan on the first verifier rejection after `cap/go`. B6: appeal and dispute steps in backend-coder's and frontend-coder's texts.
- Round 3: the integration proof, `spec/openlanes/engine/dispatcher_arbitration_spec.rb` (real `Dispatcher#run` ticks, a capped 🔴 plan never reaches backend-coder or frontend-coder, `no_go` ends it at ⭕️ with `## B1` quoting the ruling, one engine-posted PR comment, and `Live::Snapshot` carries `ruling` and `rejections: {count: 0, max: 2}`). Evals gained a `ruling` check (the final answer parsed by `Arbitration::Ruling.parse`; `run.json` carries `answer`, a live run reads it from the trace) and the case `evals/cases/arbitrator/cap-medium` with pass and fail recordings.
- Not built: the `(passed)` verdict word (see Assumptions).

## Assumptions

- `arbitrating` is derived from open stages, not a new flag, so a killed arbitrator reads `false` once the harness closes its stage.
- amended: `passed_check` runs at `mvp` only. `Config::QUALITIES` is `high|mvp` (R4 dropped `medium` and `top_notch`), so "medium and mvp" reads as `mvp`; `high` and unset run none.
- Confirmed by frontend-coder (mail #2): the three snapshot keys above are what `web/src/api/types.ts` reads, all optional there.
- amended: staff-reviewer's "passed" verdict is the existing `review-ok-not-perfect` label (`ReviewLabel::RENAMED` maps `review-passed` to it), so no `(passed)` signature word was added; the trigger reads the label, keyed by staff-reviewer's latest signature instead of the head SHA.
