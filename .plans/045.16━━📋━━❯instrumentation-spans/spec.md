---
created: 2026-11-13
starts: planning
frontend: false
depends_on: ["045.15"]
---

# Instrumentation Spans

Child of the 045.00 umbrella (SOLID Sweep, GitHub issue #95), cut from `045.00`'s `spec.md` under its decision D1: one pull request per child, built strictly in order.

## Goal

Logs and traces come from one set of dry-monitor instrumentation events: SemanticLogger to `log/openlanes.log`, spans through `opentelemetry-api` only (A13). This is new behaviour and lands in its own pull request.

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

1. (045.00 item 5) **Providers.** Existing `clock`, `event_bus`, `github`, `linear`, `logger`, `process`, `redis` stay; an OpenTelemetry provider is added (in the spans pull request). Check: `ls lib/openlanes/providers` and a resolving spec each.
1. (045.00 item 10) **Instrumentation events (A13).** Engine publishes dry-monitor events; a SemanticLogger subscriber writes `log/openlanes.log` with `-l`, `-L`, `--log-format json`; spans `run → round → plan.step → adapter.call` through `opentelemetry-api`. Check: a spec asserts one log line per event kind listed in A13 and a no-op without an SDK. **Ships as its own pull request(s), after the structure ones**, because it is new behaviour (A9).
1. (045.00 item 13) **Plan 045 acceptance command**: `just ci` green, with coverage not below the figure on `main` at the start.

Adds the OpenTelemetry provider under `lib/openlanes/providers/`; existing providers stay.

## Out of scope

- Every other child of 045.00: its scope is its own pull request.
- Tasks, `ol new`, `ol init`, planner dependency resolution: separate plans (053 to 055), which need this one first.
- Spec rewrites: A9 freezes assertions.
- Choosing an OpenTelemetry SDK or exporter: users add them (A13).
- Merging: only the maintainer merges (A11).
- Linear/GitHub behaviour changes: the seams are rewired, their contracts are not.

## Decisions

### D3 (decision, carried from 045.00) — Use dry-monitor 1.0.1; fall back to a small in-process notifier, never `EventBus`

Answered:

- 2026-11-12
- By hermes

The spans plan uses dry-monitor 1.0.1, which was verified to install and run on Ruby 4.0.6 (an event registered, subscribed to and timed). If the suite fails with it, write a small in-process notifier instead. Do not use the `EventBus` port for instrumentation.

