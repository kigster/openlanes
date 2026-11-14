---
created: 2026-11-13
starts: planning
frontend: false
depends_on: ["045.14"]
---

# Enforce Metrics Limits

Child of the 045.00 umbrella (SOLID Sweep, GitHub issue #95), cut from `045.00`'s `spec.md` under its decision D1: one pull request per child, built strictly in order.

## Goal

The last `Metrics/*` entries leave `.rubocop_todo.yml` and the A8 limits are enforced with no exemptions.

## Non-Goals

1. No behaviour change in a restructuring pull request (A9): CLI flags and output, `.plans/` files and API responses stay byte-identical.
1. No new commands, states, flags or agents.
1. No change to the state machine topology or to `Status` vocabulary.
1. No vendor tracing gem; only `opentelemetry-api` (A5, A13).
1. No rewrite of `spec/` assertions; specs may move with their class and gain examples only.
1. No touching `docs/architecture/before/`, which is frozen (A10).
1. No tasks, `ol new`, `ol init`, Leah (A7) work: those are 053/054/055 and earlier plans.

## In scope

Each item names its check, copied from `045.00`'s `spec.md`.

1. (045.00 item 1) **Metrics limits enforced.** Check: `.rubocop_todo.yml` has no `Metrics/ClassLength`, `MethodLength`, `ParameterLists` or `AbcSize` entry, `.rubocop.yml` has no `Exclude` or `AllowedMethods` under those four cops, and `bundle exec rubocop` reports 0 offenses.
1. (045.00 item 11) **Metaprogramming rules (A8).** Check: `rg "method_missing|public_send|send\(" lib` has no computed-name use; any hit is on A8's allow list.
1. (045.00 item 13) **Plan 045 acceptance command**: `just ci` green, with coverage not below the figure on `main` at the start.

"No exemptions" means no `Metrics/*` entry in `.rubocop_todo.yml` and no `Exclude`/`AllowedMethods` under those cops in `.rubocop.yml`. Other cops' todo entries (`Lint/*`, `Style/*`) are not this plan's.

## Out of scope

- Every other child of 045.00: its scope is its own pull request.
- Tasks, `ol new`, `ol init`, planner dependency resolution: separate plans (053 to 055), which need this one first.
- Spec rewrites: A9 freezes assertions.
- Choosing an OpenTelemetry SDK or exporter: users add them (A13).
- Merging: only the maintainer merges (A11).
- Linear/GitHub behaviour changes: the seams are rewired, their contracts are not.

