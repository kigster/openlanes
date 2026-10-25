---
created: 2026-10-20
lane: full
depends_on: ["039.00"]
---

# Client Registry and Remote UI

# Client Registry and Remote UI

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 6 of 7.

## What we are trying to achieve

S6, S2: a UI can point at a remote Sinatra back end (`--api-url`). Each UI registers (`POST /clients`) and gets a unique client id, with a heartbeat TTL in Redis; all clients get the same updates over SSE, relayed from Redis pub/sub. Auth is one bearer token per cluster, kept with sopsy. A UI controls its own back end and shows other nodes read-only. Every command reply names the client that sent it.

## Why it matters

Several machines run engines; a person needs to watch them all from one page and act on one.

## What already exists

`Web::App`, `Web::Events` (SSE), `Live::Node`, `Live::Commands` (consumer group), `Claims`.

## How to tell it's working?

- Two back ends on one Redis: each UI controls only its own node and sees the other read-only.
- A request without the token is refused.
- A client gone silent drops from the registry within its TTL.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

