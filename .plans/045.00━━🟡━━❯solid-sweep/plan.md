---
execution: concurrent
---

Refactor shares: the whole sweep touches at most `lib/` = 463 of 2,070 tracked files (22%) and 60,918 of 255,839 lines (24%); this umbrella pull request touches only `.plans/045.*` files (under 1%). Threshold 50% (unset in `.openlanes.yml`). Each child plan makes its own call when it is planned; the spec's "runs alone" note is theirs to apply, not the umbrella's.

# Plan 045.00: SOLID Sweep (umbrella)

`depends_on: ["049.00", "050.00", "051.00", "052.00"]` stands as written; all four are ✅ in `.plans/archive/`.

## Shape

Decision D1 in `spec.md` makes 045.00 an umbrella. The spec is a dozen pull requests, so this plan does not build any of them. It mints the child plans, one per pull request, each a `starts: planning` plan whose spec is cut from this one, and chains them through `depends_on:` so the runner builds them strictly in order (one group, one plan at a time, `Plans::Dependencies#head`).

The umbrella pull request changes `.plans/` only. No `lib/`, `spec/` or `docs/` file moves in it.

### The children

Ordinals are set once and never renumbered (`ordinal.rb`), so U1 measures before it mints and mints in this order. Each child `depends_on` the one above it; 045.01 depends on `[none]`.

| Child  | Slug                     | Scope, from `spec.md`                                                                                                  | Spec items         |
| :----- | :----------------------- | :--------------------------------------------------------------------------------------------------------------------- | :----------------- |
| 045.01 | `dry-system-wiring`      | Every component registers through `container.rb`, `Deps[...]` for collaborators, collapsed-dir key prefixes, `adapters.<name>` replacing the registry hash (A1, A2) | 3, 4, 5 (no OTel), 6 |
| 045.02 | `split-dispatcher`       | `engine/dispatcher.rb` and `dispatcher/` to the A8 limits; its `Thread.new` sites stay as they are until 045.N+1           | 2, 11, 12          |
| 045.03 | `split-executor`         | `execution/executor.rb` and its collaborators                                                                          | 2, 11, 12          |
| 045.04 | `split-plan-state`       | `plans/plan_state.rb`                                                                                                   | 2, 11, 12          |
| 045.05 | `split-run-workflow`     | RunWorkflow                                                                                                             | 2, 11, 12          |
| 045.06 … 045.K | `split-seams-batch-N` | The remaining classes over 100 lines, by descending `wc -l` at minting time, cut into batches of about 1,500 changed lines | 2, 11, 12          |
| 045.K+1 | `concurrent-ruby-threads` | Every `Thread.new` in `lib/` and `web/` server code onto concurrent-ruby; each site's primitive (pool future, `TimerTask`, `ScheduledTask`) named in the PR | 7                  |
| 045.K+2 | `result-and-judgment`   | dry-monads `Result` for fallible operations; `Judgment` port, Jev when `TYPESAFE_API_KEY` is set, otherwise the local implementation that asks through the configured coding-agent adapter (D2) | 8, 9               |
| 045.K+3 | `enforce-metrics-limits` | The last `Metrics/*` entries out of `.rubocop_todo.yml`, no `Exclude`/`AllowedMethods` under the four cops, A8 metaprogramming check | 1, 11              |
| 045.K+4 | `instrumentation-spans` | dry-monitor 1.0.1 events (D3; fallback a small in-process notifier, never `EventBus`), SemanticLogger to `log/openlanes.log`, OpenTelemetry provider and spans | 5 (OTel), 10       |

Every child carries item 13 (`just ci` green, coverage not below `main`) and the non-goals and A9 behaviour freeze verbatim.

### Order and graph

```mermaid
flowchart LR
  U1[U1 mint children] --> U2[U2 chain check]
```

Children, built later by the runner, one at a time:

```mermaid
flowchart LR
  C1[045.01 wiring] --> C2[045.02 Dispatcher] --> C3[045.03 Executor] --> C4[045.04 PlanState] --> C5[045.05 RunWorkflow] --> CB[045.06..K seam batches] --> CT[threads] --> CR[Result + Judgment] --> CE[enforce limits] --> CS[spans]
```

## Backend

### U1: Mint the child plans

- **Discipline:** back end.
- **Owns:** the new folders `.plans/045.01━━…` through `.plans/045.K+4━━…`, and each one's `spec.md`. Nothing else.
- **Must not touch:** `045.00`'s own `spec.md`, `plan.md` and `state.json`; any other plan's folder; `lib/`, `spec/`, `docs/`.
- **Depends on:** nothing.
- **What it does:**
  1. Measure the remaining seams: classes over 100 lines in `lib/` (rubocop `Metrics/ClassLength` against today's tree, not the stale numbers in `spec.md`), sorted by `wc -l`, excluding the five named in 045.01 to 045.05. Group them into batches of about 1,500 changed lines; that fixes K. Write the measured list into each batch child's spec.
  1. Mint each child in ordinal order with `openlanes create <slug words> --after <previous ordinal> --starts planning --no-draft --no-open`, then fill its `spec.md` headings (goal, non-goals, in scope with each item's check, out of scope) from the matching items of `045.00/spec.md`. Copy the checks; do not restate them loosely. If `--after` refuses without `--prs`, stop and block rather than hand-making folders.
  1. Set each child's `depends_on:` to the quoted ordinal before it (`045.01` gets `[none]`), and `frontend: false` (spec: no front-end half).
  1. Carry D2 into `result-and-judgment` and D3 into `instrumentation-spans` word for word.
- **Done when:** `openlanes resync dirs --dry-run` reports nothing to rename for any `045.*` folder, and each child's `spec.md` frontmatter holds `starts: planning`, `frontend: false` and a quoted `depends_on:`.

### U2: Integration check, the chain as the runner sees it

- **Discipline:** back end.
- **Owns:** no file. It reads only.
- **Must not touch:** everything U1 owns.
- **Depends on:** U1.
- **Must show**, through the real CLI against the real `.plans` tree, nothing stubbed:
  - `openlanes run --dry-run` (or the dependency view from 056.00 when present) lists 045.01 as the only startable child and every later child as "queued behind" its predecessor;
  - no cycle is reported, and no child depends on 045.00;
  - `bundle exec rspec spec/openlanes/plans/dependencies_spec.rb` and `just lint` stay green (the umbrella changed no code, so the whole suite must be untouched).
- **Done when:** the three outputs above are pasted into the pull request description.

U1 and U2 write no file in common; U2 runs after U1 because it reads what U1 wrote.

## Frontend

None. The spec gives the front end no change; `web/` server-side `Thread.new` sites belong to the `concurrent-ruby-threads` child.

## HTTP surface

No. Neither this plan nor any child adds or changes an HTTP API (A9 freezes API responses).

## How to test

1. `ls .plans | rg '^045\.'` lists 045.00 and 045.01 through 045.16, no gaps.
1. For each child, `head -6 .plans/045.NN*/spec.md` shows `starts: planning`, `frontend: false` and a `depends_on:` naming the child before it (`[none]` for 045.01).
1. `openlanes resync dirs --dry-run` reports nothing to rename under `045.*`.
1. `openlanes run 045.01,045.02,…,045.16 --dry-run` holds 045.02 to 045.16, each "waiting on" its predecessor, with no cycle and nothing waiting on 045.00.
1. `bundle exec rspec spec/openlanes/plans/dependencies_spec.rb` and `bundle exec rubocop` exit 0; the umbrella changes no code under `lib/` or `spec/`.
