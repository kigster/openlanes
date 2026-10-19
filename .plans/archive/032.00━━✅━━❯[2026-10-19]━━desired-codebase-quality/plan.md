# ✅ 032.00 — Codebase Quality

R4 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`. No interface work: `rey-frontend` is not started, luke owns the plan.

## Backend

### U1 Config key `desired_codebase_quality`

- `Config::KEYS` gains `desired_codebase_quality`; `QUALITIES = %i[high mvp]`; anything else is an error naming the file. `to_yaml` writes it back.
- `Config#max_rejections` defaults from it, M5's columns: `high` 2, `mvp` 1; unset stays 2. `merge.max_rejections` still beats it.
- `Config#quality_unset?` says the key is missing. amended: round 1 review, `Config#quality` had no caller and is removed.

### Scope: which rows of M5's column this plan drives

- amended: round 1 review. This plan drives two rows of M5's `high` / `mvp` column: the verdicts that go on to ification (U2) and `max_rejections` (U1).
- The other rows (default depth: high medium, mvp fast; luke, rey and hansolo models: mvp Sonnet; leah: mvp off) are not wired. They need a project-wide default under `Plans::Spec`'s per-plan `depth` and `Agents::Profile`'s models, which is a plan of its own: a follow-up, "Quality drives depth and models", still to be numbered by a person.

### U2 What the quality decides at the 👀 → 🧪 hand-off

- `Verification.from_review?(labels, quality:)`: `review-approved` always goes on; `review-ok-not-perfect` goes on under `mvp` only.
- Under `high`, an `review-ok-not-perfect` PR goes back to luke and rey: the plan moves to 🔴.
- amended: round 1 review. That send-back is a counted rejection: `Outcome#send_back_for_quality` signs it for chewie (`rejected: …; signed by harness`), so `merge.max_rejections` and the arbitrator see it, and a PR labelled the same round after round cannot loop. Labels stay as hansolo set them. `Dispatcher#approved` treats 🔴 after a hand-off as the hand-off's result; a spec pins that only `high` reaches it.
- With the key missing, the plan stays 👀 and the project is asked once (U3).

### U3 Ask once per project when the key is missing

- On the first `review-ok-not-perfect` PR with no key, `Verification::Driver` calls `Engine::QualityQuestion.ask!`: the plan whose PR raised it holds `quality_ask` in its `state.json`; any other plan waiting on the same answer stays 👀 without asking again. Built.
- `Live::Snapshot#questions` shows it as `<ordinal>/Q1`, kind `quality`, R4's two options; the page treats it as options-only, like an X<n> request. Built.
- `Live::Commands` answers `Q1` with a) high or b) mvp: the key is appended to `.openlanes.yml` (comments kept, an existing key never overwritten) and the question settles. The driver reads `Config.current` at every hand-off, so the answer counts mid-run. Built.

### U4 Builders answer every non-✅ comment

- `agents/luke-backend.md` and `agents/rey-frontend.md`: sent back, reply in each non-✅ comment's thread with a fix or a backed-up rebuttal (`gh api .../comments/<id>/replies`), listed under `## Answers, round N` in `pull-requests.md`. Built.

### U5 `openlanes init` asks it

- `--quality high|mvp`, else R4's question on a terminal; `-y` leaves the key unset so U3 asks it later. Built.

## Frontend

## Task completed when

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.

## How to test

- The key validates and drives M5's high or mvp column.
- Missing key plus a first ok-not-perfect PR shows the question once.
- Under high, every non-✅ comment gets a reply in its thread.
