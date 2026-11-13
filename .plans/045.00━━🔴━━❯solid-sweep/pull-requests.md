# Pull Requests

## Umbrella pull request: 045.00 SOLID Sweep

This pull request changes `.plans/045.*` only: no `lib/`, `spec/` or `docs/` file moves.

### U1: children minted

Measured with `bundle exec rubocop --only Metrics/ClassLength` (Max 100) on 2026-11-13: 62 classes over 100 lines in `lib/`; 53 remain after the four named seams (Dispatcher and `dispatcher/`, Executor, PlanState, RunWorkflow). Grouped by descending class length into batches of at most about 1,500 class lines, which fixes K = 12 (seven batch children). Each batch child's `spec.md` lists its classes with both counts.

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 235 | [\[045.00\](A) Solid Sweep](https://github.com/kigster/openlanes/pull/235) | Open 🟡 |

Every child's frontmatter holds `starts: planning`, `frontend: false` and a quoted `depends_on:`. D2 is carried word for word into 045.14, D3 into 045.16. Each in-scope item is copied from `045.00/spec.md` with its check.

Deviation from U1 step 2: `openlanes create --after 045` without `--status` mints a ⏪ Retroactive folder with no `spec.md`, and `--status ready_for_planning` fails its own invariant (📋 requires `plan.md`). The children were minted with `--status new`, which gives ⚪ with `starts: planning`; the lanes step then moves them past research (045.01 was moved to 📋 by the live run within a minute).

### U2: the chain as the runner sees it

`openlanes resync dirs --dir .plans --dry-run`, filtered to `045.`: nothing to rename; only lock notices.

```
  · 🔑 045.00━━🟡━━❯solid-sweep: locked by pid <pid> on <host> since 2026-11-13T08:11:45Z
  · 🔑 045.01━━📋━━❯dry-system-wiring: locked by pid <pid> on <host> since 2026-11-13T08:14:50Z
```

`openlanes run 045.01,…,045.16 --dry-run --dir .plans`: 045.01 is the only startable child (already taken by the live run, so 0 invocations); no cycle reported; no child depends on 045.00.

```
  15 plans held by dependencies:
    045.02 waiting on 045.01
    045.03 waiting on 045.02
    045.04 waiting on 045.03
    045.05 waiting on 045.04
    045.06 waiting on 045.05
    045.07 waiting on 045.06
    045.08 waiting on 045.07
    045.09 waiting on 045.08
    045.10 waiting on 045.09
    045.11 waiting on 045.10
    045.12 waiting on 045.11
    045.13 waiting on 045.12
    045.14 waiting on 045.13
    045.15 waiting on 045.14
    045.16 waiting on 045.15
```

`bundle exec rspec spec/openlanes/plans/dependencies_spec.rb`: `24 examples, 0 failures`.

`bundle exec rubocop`: `948 files inspected, no offenses detected`.

`bundle exec rspec` (whole suite, worktree): `6385 examples, 0 failures, 9 pending`, exit 0. The worktree has no code changes; the 9 pending are pre-existing.

No integration proof or e2e run beyond the above: the plan has no front end and no HTTP surface.

## Round 2: why round 1 did not reach 🟢, and what changed

Round 1 signed `Completed` with a clean worktree: the children were minted in the main checkout's `.plans/`, and the harness's publish step copies only the plan's own folder (`045.00`) into the worktree, and only once the worktree is already dirty (`Runner#publish` returns nil otherwise). Nothing was pushed, no pull request was recorded, and 🟢 Ready for Review was refused for lacking one.

Round 2 changes no code either. It puts the umbrella's actual content into the worktree so the pull request carries it:

- the sixteen child folders `045.01` to `045.16`, copied from the main checkout's `.plans/` into the worktree's `.plans/` (snapshot at copy time, `*.tmp` excluded, as the harness's own carry does for `045.00`);
- a `## How to test` section in `plan.md`, which the publisher requires before it opens a pull request.

`git status --porcelain` in the worktree lists exactly the 16 child folders as untracked and nothing else.

Round 2 checks, worktree: `bundle exec rubocop` → `948 files inspected, no offenses detected`, exit 0; `bundle exec rspec` → `6385 examples, 0 failures, 9 pending`, exit 0.

## Round 3: review fixes

No code change. Three edits to what the pull request carries:

- **F1 (and F201):** 045.01's folder is removed from the pull request entirely (`git rm`, four files: `plan.md`, `pull-requests.md`, `spec.md`, `state.json`). 045.01 was already at 🟡 on its own branch when the umbrella was reviewed, so any copy here, fresh or not, lands on `main` beside the folder its own pull request adds, under a different state emoji and with no conflict to warn anyone. Its own pull request carries `spec.md`. `plan.md` ("The children", U1 "Owns", "How to test" step 1) says so. The pull request now carries 045.00 and 045.02 to 045.16.
- **F3:** `Resync::Prs` (`lifecycle/resync.rb:402`, 121 lines) moves from batch 6 (045.11) to batch 5 (045.10), beside `Resync::Dirs`, so `resync.rb` is rewritten by one pull request. Batch 5 is now 10 classes, 1,535 class lines; batch 6 is 10 classes, 1,280. Both `spec.md` files carry a note on why the row is out of length order. Edited in the live `.plans/` and copied into the worktree.
- **F203, F101:** `plan.md`'s child table names the minted ordinals (045.06 to 045.12 batches, 045.13 to 045.16) instead of `045.K`; the host name and pid in the U2 lock lines above are redacted.

Round 3 checks, worktree, 2026-11-13:

- `bundle exec rubocop` → `948 files inspected, no offenses detected`, exit 0.
- `bundle exec rspec` → `6385 examples, 0 failures, 9 pending`, coverage 99.22%, exit 0. No code changed; the 9 pending are pre-existing.
- `openlanes resync dirs --dry-run` on the live `.plans/`: nothing to rename under `045.*`; the only line is the lock notice for 045.00 (held by this run).
- `git status --porcelain` in the worktree: four `D` lines (045.01's folder) and two `M` lines (045.10 and 045.11 `spec.md`); nothing else.

## Answers, round 3

Pull request 235 has no inline review threads; the three reviews are issue comments, so each is answered here, by comment id, and the reviewer's finding numbers are used.

| Comment | Finding | Answer | What |
| :------ | :------ | :----- | :--- |
| IC_kwDOVIKkL88AAAABmDB9wA (staff-reviewer) | F1 | fix | 045.01's folder dropped from the pull request; `plan.md` updated. |
| IC_kwDOVIKkL88AAAABmDB9wA (staff-reviewer) | F2 | rebuttal | Agreed, and the finding itself says it is a follow-up, not this pull request. The empty `plan.md` is the definition of 📋, not an accident: `STATUSES` in `lib/openlanes/plans/status.rb` declares Ready for Planning with `requires: spec.md, plan.md`, the note "`plan.md` exists and is still blank, waiting for the planner", and `invariant: blank_plan`, so `resync dirs` flags a 📋 folder whose `plan.md` already holds a plan heading. Having `create` omit the file, or the invariant reject an empty one, would change the state's contract under `lib/`, which this umbrella forbids ("changes `.plans/` only"). Left for a plan of its own. |
| IC_kwDOVIKkL88AAAABmDB9wA (staff-reviewer) | F3 | fix | `Resync::Prs` moved into batch 5 with `Resync::Dirs`; both specs amended. |
| IC_kwDOVIKkL88AAAABmC_o_Q (design-reviewer) | F201 | fix | Same as F1. The reviewer's "carry as minted with a fresh `state.json`" was not taken: a minted copy still lands beside 045.01's own folder on `main` when the two pull requests merge in either order. Lock lines redacted. |
| IC_kwDOVIKkL88AAAABmC_o_Q (design-reviewer) | F202 | rebuttal | The umbrella `plan.md` requires it: "Every child carries item 13 … and the non-goals and A9 behaviour freeze verbatim", and U1 step 2 says "Copy the checks; do not restate them loosely." Each child is planned and built alone, by an agent whose card is that child's `spec.md`; a pointer to another plan's non-goals is a read the agent may not make. Drift is bounded by the chain: the children are built strictly in order, and the umbrella's spec is frozen once its pull request merges. |
| IC_kwDOVIKkL88AAAABmC_o_Q (design-reviewer) | F203 | fix | Child table in `plan.md` now names 045.06 to 045.16. |
| IC_kwDOVIKkL88AAAABmC_o_Q (design-reviewer) | F204 | rebuttal | 045.01's `plan.md` is no longer in this pull request (F1). The premise and the U4 file list belong to 045.01's own pull request and its reviewers. |
| IC_kwDOVIKkL88AAAABmDAKRQ (security-reviewer) | F101 | fix | Host name and pid redacted from the pasted lock lines. |

## Findings: design-reviewer

### F201 [minor] .plans/045.01━━🟡━━❯dry-system-wiring/state.json:1
The umbrella PR carries a mid-build snapshot of 045.01 taken from another worktree: `state.json` (state `building`, backend-coder session ids, absolute `/Users/hermes/...` cwd, an `Interrupted` resume record), `plan.md`, and a `pull-requests.md` with U4 and U6 unchecked. The 045.01 PR owns that same folder. Scenario: the umbrella merges first, then the 045.01 PR adds the same paths with different content (and a different state emoji in the folder name), so the maintainer hits add/add conflicts. Worse, `main` gets a `building` plan with a stale session and resume record that no live run is attached to. Carry 045.01 as minted (`spec.md` plus a fresh `state.json`) and leave its progress to its own PR. The same goes for the host and pid in the lock lines pasted into `pull-requests.md` (`<host>`, pid <pid>).

### F202 [minor] .plans/045.02..045.16/spec.md:30
The seven non-goals and the six out-of-scope bullets are pasted verbatim into all 16 child specs, and each child's four-item "In scope" block repeats items 2, 11, 12 and 13 of the umbrella spec. This is the fact-written-twice problem the codebase's own rules warn about. Scenario: a non-goal in 045.00 is reworded (A9, say), and 15 children keep the old text with nothing to say they are stale. Have each child point to the umbrella's non-goals and keep only what is specific to it (its files, its measured class table).

### F203 [minor] .plans/045.00━━🟡━━❯solid-sweep/plan.md:20
`plan.md` still describes the children with the symbolic ordinals `045.06 … 045.K` and `045.K+1`..`K+4`, while `pull-requests.md` holds the real table (K = 12, 045.13 to 045.16). The plan keeps one half of the mapping and the PR doc the other, and the two can drift. Scenario: a reader of `plan.md` alone cannot tell that `concurrent-ruby-threads` is 045.13. Replace the symbols with the minted ordinals now that they are fixed.

### F204 [minor] .plans/045.01━━🟡━━❯dry-system-wiring/plan.md:12
The plan states that "Nothing under `lib/` includes `Deps[...]` yet", but the 045.00 research cites `engine/upkeep.rb:55` as an existing use. U4's ownership is defined by an `rg` command ("about 26 files") instead of a file list, so the `alock` claims and the U2/U3 disjointness check cannot be done up front. Correct the premise and have U4 list its files once it has swept.

## Findings: security-reviewer

### F101 [minor] pull-requests.md:46

🔓 The U2 output pasted into the pull request records a machine hostname, pid and lock timestamps (`locked by pid <pid> on <host>`). Not exploitable. A public repository now carries an internal host name. Scenario: anyone reading the PR learns the maintainer's machine name; no access follows from it. Redact the host before the PR is public.

Checked and clean: no secrets, tokens or credentials in the diff (only the env var name `TYPESAFE_API_KEY`); no code, dependency or file-permission changes (`.plans/` only); the plan documents contain no text posing as harness instructions.

## Findings: staff-reviewer

### F1 [critical] .plans/045.01━━🟡━━❯dry-system-wiring/state.json:1

The umbrella PR carries a mid-build snapshot of another live plan: 045.01's folder at 🟡 with its `plan.md`, a half-done `pull-requests.md` (U4, U6 unchecked) and a `state.json` whose last stage is backend-coder `Started`. U1 owns only each child's folder and `spec.md`; this goes past that. 045.01's own branch (`hermes/045.01-dry-system-wiring`) was cut from `bca5b1b0`, before this PR, so it holds no 045.01 folder; `Publisher#carry_plan` only removes same-ordinal folders already in its checkout, and `catch_up` pushes but never rebases.
Scenario: maintainer merges #235, then 045.01's PR (which adds `.plans/045.01━━👀━━❯dry-system-wiring`) without a rebase. Expected: one 045.01 folder on `main`. Actual: two, `045.01━━🟡` (stale, frozen at U4-not-started) and `045.01━━👀`, two paths so git reports no conflict. Fix: drop 045.01's `plan.md`, `pull-requests.md` and `state.json` from this PR (carry its `spec.md` only, or nothing for 045.01), or have 045.01 rebase on `main` before its publish.

### F2 [minor] .plans/045.03━━📋━━❯split-executor/plan.md:1

Fourteen children (045.03 to 045.16) ship an empty `plan.md`, and 045.02's is git's rename of 045.00's old empty `plan.md`. The 📋 folder name then rests on a zero-byte file. Scenario: a reader runs `resync dirs` and nothing gets flagged, but there is no plan in any of those files. Consider having `openlanes create` put no `plan.md` in a 📋 folder, or have the invariant reject an empty one. That is a follow-up, not this PR.

### F3 [minor] .plans/045.11━━📋━━❯split-seams-batch-6/spec.md:43

`lib/openlanes/lifecycle/resync.rb` is split between batch 5 (class at :46) and batch 6 (class at :402), so two sequential PRs rewrite one file. Scenario: batch 5 splits resync.rb, the line-402 class moves or shifts, and batch 6's table points at a line that no longer exists. The "re-measure when this plan starts" note softens this. Putting both classes in one batch is cleaner.
