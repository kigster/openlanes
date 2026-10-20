---
created: 2026-10-20
lane: full
---

# Solid Seams and Thread Safety

# SOLID Seams and Thread Safety

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 1 of 7.

## What we are trying to achieve

Plan 1 of the distributed-engine epic (S1, S10 in `docs/decisions/decisions-on-distributed-engine-and-solid-refactor.md`). Introduce the seams the rest of the epic builds on, about 80% SOLID rather than pedantic and in a functional style: an `EventBus` port (Redis and in-memory), `Clock` and `Process` ports, and an `AgentAdapter` capability contract. Then audit shared mutable state for thread safety: frozen `Data` by default, a `Mutex` or `Concurrent::Map` only where one is needed. No broad renames.

## Why it matters

The journal, recovery, watchdog and multi-node UI plans all need to swap the bus, the clock and the process layer under test, and to run more agents concurrently without races.

## What already exists

Facades per namespace; `Live::Store`/`MemoryStore`; `Adapters::Base` with claude, codex, pi; `Claims` already mutex-guarded.

## How to tell it's working?

- Engine, Live and Web publish and subscribe only through `EventBus`.
- Every adapter declares its capabilities, and the Executor branches on capabilities, never on adapter names.
- A thread-safety inventory of shared state is written down, and a stress spec runs N concurrent dispatch ticks green.
- Runs alone under the global lock (034).

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

