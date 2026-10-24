---
created: 2026-10-20
starts: research
depends_on: ["041.00", "045.00"]
---

# Stuck Plan Watchdog

# Stuck Plan Watchdog

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 5 of 7.

## What we are trying to achieve

S5: two triggers (the clock running low, and a stall of no output and no worktree change for `stall_minutes`, default 10) feed a ladder: ask the agent for more time in 5-minute chunks up to 30 (absorbs 027); interrupt and resume the session, at most twice; then open a `blocked.md` question quoting the last output and any conflicting plan.

Conflicting plans are found by file overlap. The explanation comes from the `Judgment` port added in 045: Jev (TypeSafe) only when `TYPESAFE_API_KEY` is set, otherwise the default adapter's cheapest model, and the overlap alone if both fail (S18).

## Why it matters

No plan may sit started, unfinished and making no progress.

## What already exists

`Engine::Extensions` (`X<n>`), `Execution::Clock`, D7 and E1 decisions.

## How to tell it's working?

- Invariant spec: every in-flight plan is progressing, waiting on a person, or terminal.
- Simulated stalls walk the ladder on a fake clock.
- The journal records each rung.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

