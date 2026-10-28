---
created: 2026-10-16
starts: planning
depends_on: ["030.00"]
---

# Three Reviewers

## What we are trying to achieve

Review every pull request from three angles at once: `staff-reviewer` (correctness, readability, runtime failures, performance), `security-reviewer` (vulnerabilities) and `design-reviewer` (code organisation, SOLID, small files, swappable implementations). Each runs on its own coding agent where several are available, reports one verdict, and the dispatcher turns the verdicts into the PR's label.

Decided in `docs/decisions/decisions-on-agent-names-models-and-reviewers.md` (V1 to V8), which supersedes the roster of R1 and the pooled emoji count of R3 in `docs/decisions/decisions-on-three-reviewers-and-auto-merge.md`. R2's comment format (the "Reviewed by …" header, one emoji verdict per comment) stands.

## Why it matters

Three angles catch what one reviewer misses, and different coding agents catch different things.

## What already exists

- `staff-reviewer` handles `ready_for_review` and `in_review` alone, labels the PR itself through `openlanes review`, and its ledger note decides where the folder goes.
- `Plans::Verdict` pools the emoji of every comment into a label (R3); nothing calls it yet.
- `Agents::Names` already holds `SECURITY_REVIEWER` and `DESIGN_REVIEWER`, listed as `PLANNED`.
- Two agents handling one state already run together as a pair (the coders).

## How to tell it's working?

- A `starts: planning` plan in review gets three reviewers at once; a `starts: building` plan gets `staff-reviewer` alone (V5).
- Each review opens with the R2 header, and each comment with an allowed emoji.
- The folder moves and the PR is labelled only after every reviewer has reported, by V4: any rejection rejects; two `great` of three approve; otherwise `review-passed`.
- `review-ok-not-perfect` is renamed `review-passed` on the repository, and PRs carrying it keep it.

## How to test

- Dispatcher specs with three stubbed reviewers finishing in every order and every verdict mix.
- A label-sync spec renaming `review-ok-not-perfect` in place.
- `openlanes agents` lists both new reviewers; the agent-name drift spec has nothing `PLANNED`.
