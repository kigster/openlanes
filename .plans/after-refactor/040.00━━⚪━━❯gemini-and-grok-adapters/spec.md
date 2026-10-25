---
created: 2026-10-20
starts: research
depends_on: ["038.00"]
---

# Gemini and Grok Adapters

# Gemini and Grok Adapters

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 3 of 7.

## What we are trying to achieve

S8: adapters for Google's `gemini` CLI (headless stream-json) and xAI's `grok` CLI (headless JSON), built on the capability contract from plan 1. The Executor degrades where a capability is missing; with no deny-list, for example, the Boundary after-check is the only guard.

## Why it matters

No vendor lock-in: every phase can run on any of claude, codex, pi, gemini or grok.

## What already exists

`Adapters::Base`, `Claude`, `Codex`, `Pi`, `Stream`; per-phase adapter/model in spec frontmatter.

## How to tell it's working?

- `adapter: gemini` and `adapter: grok` run a phase end to end against recorded transcripts.
- Capabilities are reported by `openlanes agents`.
- No spec reaches the network.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

