---
created: 2026-11-13
starts: planning
frontend: false
depends_on: ["045.13"]
---

# Result And Judgment

Child of the 045.00 umbrella (SOLID Sweep, GitHub issue #95), cut from `045.00`'s `spec.md` under its decision D1: one pull request per child, built strictly in order.

## Goal

Fallible operations return dry-monads `Result`, and a vendor-neutral `Judgment` port selects Jev only when `TYPESAFE_API_KEY` is set (S15, S19).

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

1. (045.00 item 8) **Result returns.** Fallible operations that today raise for control flow or return nil/false return dry-monads `Result` (pattern at `lifecycle.rb:35`, `supervision/registration.rb:13`). Check: each converted method has a YARD `@return [Dry::Monads::Result]` and a success and a failure example; callers' existing CLI output is unchanged.
1. (045.00 item 9) **Judgment port.** A vendor-neutral `Judgment` component; the Jev implementation is selected only when `TYPESAFE_API_KEY` is set, otherwise a local default. Check: specs for both branches by stubbing the environment.
1. (045.00 item 13) **Plan 045 acceptance command**: `just ci` green, with coverage not below the figure on `main` at the start.

Callers' CLI output is unchanged.

## Out of scope

- Every other child of 045.00: its scope is its own pull request.
- Tasks, `ol new`, `ol init`, planner dependency resolution: separate plans (053 to 055), which need this one first.
- Spec rewrites: A9 freezes assertions.
- Choosing an OpenTelemetry SDK or exporter: users add them (A13).
- Merging: only the maintainer merges (A11).
- Linear/GitHub behaviour changes: the seams are rewired, their contracts are not.

## Decisions

### D2 (decision, carried from 045.00) — Local `Judgment` asks through the configured coding-agent adapter

Answered:

- 2026-11-12
- By hermes

When `TYPESAFE_API_KEY` is unset, `Judgment` is a local implementation that asks through the configured coding-agent adapter.

