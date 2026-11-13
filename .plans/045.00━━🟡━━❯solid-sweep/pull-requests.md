# Pull Requests

## Umbrella pull request: 045.00 SOLID Sweep

This pull request changes `.plans/045.*` only: no `lib/`, `spec/` or `docs/` file moves.

### U1: children minted

Measured with `bundle exec rubocop --only Metrics/ClassLength` (Max 100) on 2026-11-13: 62 classes over 100 lines in `lib/`; 53 remain after the four named seams (Dispatcher and `dispatcher/`, Executor, PlanState, RunWorkflow). Grouped by descending class length into batches of at most about 1,500 class lines, which fixes K = 12 (seven batch children). Each batch child's `spec.md` lists its classes with both counts.

| Child  | Slug                      | depends_on |
| :----- | :------------------------ | :--------- |
| 045.01 | `dry-system-wiring`       | `[none]`   |
| 045.02 | `split-dispatcher`        | 045.01     |
| 045.03 | `split-executor`          | 045.02     |
| 045.04 | `split-plan-state`        | 045.03     |
| 045.05 | `split-run-workflow`      | 045.04     |
| 045.06 | `split-seams-batch-1`     | 045.05     |
| 045.07 | `split-seams-batch-2`     | 045.06     |
| 045.08 | `split-seams-batch-3`     | 045.07     |
| 045.09 | `split-seams-batch-4`     | 045.08     |
| 045.10 | `split-seams-batch-5`     | 045.09     |
| 045.11 | `split-seams-batch-6`     | 045.10     |
| 045.12 | `split-seams-batch-7`     | 045.11     |
| 045.13 | `concurrent-ruby-threads` | 045.12     |
| 045.14 | `result-and-judgment`     | 045.13     |
| 045.15 | `enforce-metrics-limits`  | 045.14     |
| 045.16 | `instrumentation-spans`   | 045.15     |

Every child's frontmatter holds `starts: planning`, `frontend: false` and a quoted `depends_on:`. D2 is carried word for word into 045.14, D3 into 045.16. Each in-scope item is copied from `045.00/spec.md` with its check.

Deviation from U1 step 2: `openlanes create --after 045` without `--status` mints a ⏪ Retroactive folder with no `spec.md`, and `--status ready_for_planning` fails its own invariant (📋 requires `plan.md`). The children were minted with `--status new`, which gives ⚪ with `starts: planning`; the lanes step then moves them past research (045.01 was moved to 📋 by the live run within a minute).

### U2: the chain as the runner sees it

`openlanes resync dirs --dir .plans --dry-run`, filtered to `045.`: nothing to rename; only lock notices.

```
  · 🔑 045.00━━🟡━━❯solid-sweep: locked by pid 9345 on imac27.re1.re since 2026-11-13T08:11:45Z
  · 🔑 045.01━━📋━━❯dry-system-wiring: locked by pid 9345 on imac27.re1.re since 2026-11-13T08:14:50Z
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
