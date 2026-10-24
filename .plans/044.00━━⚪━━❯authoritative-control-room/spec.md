---
created: 2026-10-20
starts: research
depends_on: ["043.00"]
---

# Authoritative Control Room

# Authoritative Control Room

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 7 of 7.

## What we are trying to achieve

S2, S3: `openlanes web --authoritative` holds the single Redis slot (`SET NX EX 30`, renewed every 10s). A second one is refused; `--take-over` evicts the holder, which drops to per-node mode. It talks to every engine over a bidirectional pub/sub channel, and nodes answer one to one. Its page is a superset of the per-node page, with cluster-wide controls. Per-node UIs keep control of their own nodes, and the last command wins.

## Why it matters

One person can steer every node from any machine, with or without a local engine.

## What already exists

Plan 6's registry and remote API; the command stream.

## How to tell it's working?

- Only one authoritative UI at a time, and a crashed holder's slot frees within 30s.
- A cluster-wide Start reaches every node, and each node's reply comes back addressed to the authoritative client.
- The per-node pages see those commands.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

