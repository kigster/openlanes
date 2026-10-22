---
created: 2026-10-20
starts: research
depends_on: ["038.00"]
---

# Solid Sweep

# SOLID Sweep

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 8 (S19).

## What we are trying to achieve

The broad refactor that 038 deliberately left out (S10). Bring the codebase to about 80% SOLID, not pedantically: one responsibility per class, collaborators injected through the 038 ports, namespaces reached only through their facades, and a functional core (pure functions over frozen `Data`, side effects at the edges). Move the 24 bare `Thread.new` call sites to concurrent-ruby primitives, with fallible operations returning dry-monads `Result` (S15). Add a vendor-neutral `Judgment` port for narrow typed decisions. Jev (TypeSafe) is one backend, used only when `TYPESAFE_API_KEY` is set; otherwise the project's default adapter answers with its cheapest model (S18).

## Why it matters

Each plan after this one gets cheaper to build and to test, and concurrency stops depending on someone remembering which object is shared.

## What already exists

The 038 seams (`EventBus`, `Clock`, `Process`, the adapter capability contract); facades per namespace; dry-monads and concurrent-ruby already in the gemspec; `docs/REFACTOR.md`.

## How to tell it's working?

- No bare `Thread.new` is left in `lib/`, and a spec enforces that.
- No class reaches into another namespace except through its facade or a value type, and a spec enforces that.
- With `TYPESAFE_API_KEY` unset, no code path loads or calls TypeSafe, and specs prove it. With it set, `Judgment` uses Jev and falls back to the adapter LLM on error.
- `just ci` is green and coverage does not drop.
- Runs alone under the global lock (034), after 038.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

