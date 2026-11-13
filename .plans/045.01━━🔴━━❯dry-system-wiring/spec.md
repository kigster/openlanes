---
created: 2026-11-13
starts: planning
frontend: false
depends_on: [none]
---

# Dry System Wiring

Child of the 045.00 umbrella (SOLID Sweep, GitHub issue #95), cut from `045.00`'s `spec.md` under its decision D1: one pull request per child, built strictly in order.

## Goal

Every component registers through dry-system, collaborators arrive by `Deps[...]`, collapsed directories keep their key prefix, and coding agents resolve by name as `adapters.<name>` (A1, A2), with no change in behaviour.

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

1. (045.00 item 3) **dry-system wiring.** Every component under `lib/openlanes` registers through `lib/openlanes/container.rb`; hand-built collaborators become `Deps[...]`. Check: `rg "\.new\(" lib` outside factories and value types finds no collaborator construction that has a registered key; `spec` resolves each provider key from the container.
1. (045.00 item 4) **Collapsed directories keep their key prefix** (`container.rb:10-12`): `support/clock.rb` is `support.clock`. Check: a spec resolves one key from `support/` and one from `cli/<command>/`.
1. (045.00 item 5) **Providers.** Existing `clock`, `event_bus`, `github`, `linear`, `logger`, `process`, `redis` stay; an OpenTelemetry provider is added (in the spans pull request). Check: `ls lib/openlanes/providers` and a resolving spec each.
1. (045.00 item 6) **Adapters registered by name.** `claude`, `codex`, `pi`, `grok`, `gemini` resolve as `adapters.<name>`; the hand-written registry hash in `adapters.rb` is deleted (A2). Check: `rg "registry" lib/openlanes/adapters.rb` finds no hash literal, and `known?`/`for` answer as before in the existing adapter specs.
1. (045.00 item 13) **Plan 045 acceptance command**: `just ci` green, with coverage not below the figure on `main` at the start.

The container, `Deps`, the existing providers and the adapters registry. The OpenTelemetry provider is not this plan's: it ships with `instrumentation-spans`.

## Out of scope

- Every other child of 045.00: its scope is its own pull request.
- Tasks, `ol new`, `ol init`, planner dependency resolution: separate plans (053 to 055), which need this one first.
- Spec rewrites: A9 freezes assertions.
- Choosing an OpenTelemetry SDK or exporter: users add them (A13).
- Merging: only the maintainer merges (A11).
- Linear/GitHub behaviour changes: the seams are rewired, their contracts are not.

