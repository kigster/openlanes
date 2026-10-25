---
created: 2026-10-20
lane: full
depends_on: ["039.00"]
---

# Idle Start and Crash Recovery

# Idle Start and Crash Recovery

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 4 of 7.

## What we are trying to achieve

S4, S7: `openlanes start` comes up idle and waits for Start All, Start plan or Stop, except that it resumes in-flight plans found in the journal. Agents write to per-run NDJSON files and run in their own session, so they outlive the engine. On restart the engine checks each PID together with its start time, re-attaches by tailing from the journaled offset, and resumes dead agents with `--resume` or a fresh round. `openlanes run` still starts at once; `--autostart` restores today's behavior for `start`.

## Why it matters

A crash, a kill or a reboot never loses work in flight, and starting the web never launches work nobody asked for.

## What already exists

`Execution::Child` (pipe plus pgroup), `Control` files, `StartWorkflow`, `StateFile`.

## How to tell it's working?

- `kill -9` of the engine, then a restart: surviving agents are re-attached, dead ones are resumed, and nothing runs twice.
- A reused PID is not mistaken for an agent.
- A fresh `start` with nothing in flight runs no agent until a command arrives.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

