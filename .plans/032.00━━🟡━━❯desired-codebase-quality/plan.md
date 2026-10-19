# Plan 032.00 — Desired Codebase Quality

R4 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`. No interface work: `rey-frontend` is not started, luke owns the plan.

## Backend

### U1 Config key `desired_codebase_quality`

- `Config::KEYS` gains `desired_codebase_quality`; `QUALITIES = %i[high mvp]`; anything else is an error naming the file. `to_yaml` writes it back.
- `Config#max_rejections` defaults from it, M5's columns: `high` 2, `mvp` 1; unset stays 2. `merge.max_rejections` still beats it.
- `Config#quality` reads `:high` when unset; `Config#quality_unset?` says the key is missing.

### U2 What the quality decides at the 👀 → 🧪 hand-off

- `Verification.from_review?(labels, quality:)`: `review-approved` always goes on; `review-ok-not-perfect` goes on under `mvp` only.
- Under `high`, an `review-ok-not-perfect` PR goes back to luke and rey: the plan moves to 🔴.
- With the key missing, the plan stays 👀 and the project is asked once (U3).

### U3 Ask once per project when the key is missing

- On the first `review-ok-not-perfect` PR with no key, the R4 question is put to the person once per project, in the drawer; the answer writes the key into `.openlanes.yml`. Not built this round.

### U4 Builders answer every non-✅ comment

- `agents/luke-backend.md` and `agents/rey-frontend.md`: sent back, reply in each non-✅ comment's thread with a fix or a backed-up rebuttal. Not built this round.

### U5 `openlanes init` asks it

- Not built this round.

## Frontend

## Task completed when

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.

## How to test

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.
