---
created: 2026-10-16
lane: full
---

# Durable Run Events

Source: GitHub issue #50, https://github.com/kigster/openlanes/issues/50 — "Record durable run events and outcome metrics"

## Problem

The live control room and plan artifacts expose useful run information, but OpenLanes needs a durable, queryable history to answer product questions: how often agents block, how much human intervention they need, how many runs produce PRs, and which PRs are accepted or merged. Redis is well suited to live coordination; it should not be the only record for cross-run reporting.

## Proposal

Add a small event model and storage boundary for plan, run, agent, block/answer, and PR lifecycle events. Keep Redis for live state. Start with a local/self-hosted durable sink and make PostgreSQL an optional backend if that is the chosen deployment path.

## Acceptance criteria

- Define stable, idempotent events for run/agent start and completion, blocks and human answers, PR opened/reviewed/merged/closed, and relevant failures.
- Distinguish block count from the number of unique agent runs that needed feedback.
- Capture timestamps, project/plan/run/agent identifiers, adapter/model, and provider-reported usage when available; label estimates as estimates.
- Provide basic aggregate queries for completion rate, intervention rate, time-to-answer, PR outcome, and cost/usage by run or model.
- Keep source code, prompts, and conversation text out of analytics storage by default.
- Make persistence optional for a single-machine install and document multi-machine consistency behavior.

## What we are trying to achieve

- A stable, idempotent event record for plan, run, agent, block/answer and PR lifecycle events, kept beyond Redis.
- Aggregate answers: completion rate, intervention rate, time-to-answer, PR outcome, cost/usage by run or model.
- No source code, prompts or conversation text in analytics storage by default.
- Persistence optional for a single-machine install.

## Why it matters

Redis holds only live coordination state, so cross-run questions (how often agents block, how many runs yield PRs, which PRs get merged) cannot be answered once a run ends or Redis is flushed. `.plans/` artifacts show one plan at a time, not history.

## What already exists

- `lib/openlanes/live/run_record.rb` (`RunRecord`): keeps `RunState` in Redis and mirrors it to `.plans/openlanes-state.json`, so state survives a Redis flush. Closest precedent for a file-backed durable copy.
- `lib/openlanes/live/store.rb` and `live/memory_store.rb`: the Redis store and its in-memory double; the seam a durable sink would sit beside.
- `lib/openlanes/live/meter.rb`, `live/run_state.rb`, `live/run_record.rb`: live token and usage accounting. Not read in detail; check whether it reads provider-reported usage.
- `lib/openlanes/engine/state_file.rb`, `engine/tally.rb`, `engine/progress_log.rb`: restart state and the per-run cost/progress record the run shows.
- `lib/openlanes/plans/plan_state.rb` with `schemas/plan-state.schema.json`: per-plan `state.json` (stages, signatures, messages, question conversions). Per-plan, not cross-run.
- `lib/openlanes/plans/pull_requests.rb` and `plans/pull_request.rb`: rows parsed from `pull-requests.md`, the only PR-outcome record on disk.
- `lib/openlanes/plans/ledger.rb`, `plans/mailbox.rb`: dated agent notes and inter-agent messages.
- `lib/openlanes/execution/transcript.rb`: parses `stream-json` output. Raw NDJSON traces go to `Dir.tmpdir/openlanes-traces`, outside the repo, per `CLAUDE.md`.
- `lib/openlanes/vcs/github.rb`: the `gh` seam, a source for PR opened/merged/closed facts.
- `docs/decisions/decisions-on-blocks-and-escalation.md`: block semantics, relevant to block vs unique-run counts.
- Not found: any event model, durable sink, or PostgreSQL integration in `lib/`. I did not finish searching `lib/openlanes/web/events.rb` or `live/subscriber.rb`, which may already emit events.

## What research needs to settle

- Does `live/subscriber.rb` or `web/events.rb` already form an event stream that can be persisted instead of a new model?
- Which sink for a single machine: append-only JSONL, SQLite, or PostgreSQL? The issue leans PostgreSQL as optional; the repo has no decision on it yet.
- Event identity for idempotency: which key (plan `NNN.MM`, run id, round, agent, block id)?
- Which provider usage fields are reliable per adapter (`claude`, `codex`, `pi`), and where estimates must be labelled.
- How multi-machine writes stay consistent when two nodes share Redis and one repo.
- Retention and redaction rules for prompts and conversation text.

