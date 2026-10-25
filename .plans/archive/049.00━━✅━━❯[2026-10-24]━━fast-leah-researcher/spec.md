---
created: 2026-10-24
starts: research
depends_on: [none]
---

# Fast Leah Researcher

## What we are trying to achieve

Leah finishes research in minutes, not half an hour (A7 in `docs/decisions/decisions-on-dry-rb-architecture.md`). She scans the repository for what can be reused, runs a few web searches for an existing gem, crate or package, and writes `## Research` as three parts: Reuse in this repo, Existing components, Open questions for yoda. No sub-agent waves, no test-suite run, no settled questions. Timeout 300 seconds, model `haiku`.

## Why it matters

Today she fans out sub-agent waves, runs the test suite and answers every open question herself, and routinely runs for half an hour against a 1200-second timeout, stalling every plan behind her.

## What already exists

`agents/leah-researcher.md` (her definition and timeout), her eval cases under `evals/cases/leah-researcher/`, and yoda-writer, who reads her chapter.

## What research needs to settle

- Which eval cases assert the old chapter shape and must change.
- Whether yoda's prompt depends on the old `### Findings, Conclusion & References` heading.
