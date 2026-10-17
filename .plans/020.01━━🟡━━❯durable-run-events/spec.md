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

> [!NOTE]
>
> [2026-10-16 06:15:36 PM PDT] [ agent: leah-researcher   status: **Interrupted, round 1 (harness died)** ]

## Research

Method: read the code the feature touches; no test run was needed for these answers. Two web searches, dated 2026-10-16, for the provider output formats the repo does not document.

### Answers

**Q1. Can an existing stream be persisted instead of a new model?**
No. `web/events.rb:1-30` is a polled SSE view of Redis snapshots, replies, chat and copilot turns. It keeps no history and drops nothing into storage. `live/subscriber.rb:1-20` is a Redis pub/sub connection, so messages not read are lost. Neither is a source of record. Build the event model from the engine's own transitions (`engine/dispatcher.rb`, `live/run_record.rb:39`), not from the view layer.

**Q2. Which sink on one machine?**
Recommendation: append-only JSONL, one file per node, outside the repo. Reasons: no new dependency (`gemspec:58-89` lists no `sqlite3` or `pg`), it survives Redis flush, and `RunRecord` already uses a file mirror (`live/run_record.rb:1-20`). Put it beside the run state that 021.00 moves (see contradictions). SQLite is the next step if aggregate queries get slow. PostgreSQL stays optional: the repo has no decision on it, and the global rule requires a PostgreSQL class to be written into this project's `CLAUDE.md`, which it does not state.

**Q3. Idempotency key.**
Recommendation: `event_id = sha256(node_id, checkout_id, ordinal, round, agent, invocation_start, kind, seq)`. Evidence: `Live::Meter` already keys one invocation by `[agent, round, since]` (`live/meter.rb:1-20`, `since` on `engine/board.rb:53`); `Live::Node` gives `id` (digest of `user@host`) and `checkout_id` (`live/node.rb:1-20`); `RunState#seq` is monotonic only inside one node (`live/run_state.rb:21,50,62`), so it cannot be a global key. Replaying the same invocation must produce the same `event_id`, so a duplicate write is a no-op on a unique index or a line-level dedupe at read time.

**Q4. Reliable usage per adapter.**
- `claude`: reliable. The `result` event's `usage` is the invocation's final accounting and replaces the running total (`execution/transcript.rb:430-433`, `502-512`). Only `message_delta` is trusted mid-stream; `assistant` output tokens are placeholders (`transcript.rb:327-348`). Sub-agent spend is left out of the `result` figure (`transcript.rb:422-429`), so label it incomplete when `subagent_stats.spawned > 0`.
- `codex`: partial. `adapters/stream.rb:148-153` adds `input_tokens`/`output_tokens` per event and does not add `cached_input_tokens` to the total. Codex prices nothing: `adapters/codex.rb` has no `models`, and `adapters/base.rb:44` returns `[]`. So `Meter#for` (`live/meter.rb:43-47`) prices every codex spend at `0`, which reads as free. Store codex cost as unknown (`null`), not `0`.
- `pi`: same as codex. No model table (`adapters/pi.rb`, `base.rb:44`), and usage is read by shape, so it is unverified.
- Estimates: `Model#cost` (`adapters/model.rb:25`) ignores cache reads and cache writes, which the Claude table itself flags (`adapters/claude.rb:18-22`). Every cost computed here is an estimate and must carry `estimated: true`. Provider-reported cost (`total_cost_usd`) is not read anywhere in `lib/`. Third-party reports disagree on whether `total_cost_usd` is per call or cumulative per session under stream-json, and one reports a 10× overstatement, so do not store it without checking against real output: [claudeissues 83239](https://claudeissues.com/issue/83239-docs-total-cost-usd-is-cumulative-per-session-under-output-format-stream-json-bu), [claudeissues 53371](https://claudeissues.com/issue/53371-total-cost-usd-returns-incorrect-values-10x-too-high), both retrieved 2026-10-16. Codex `turn.completed` carries `input_tokens`, `cached_input_tokens`, `output_tokens`, but the field set varies by Codex version: [littlebearapps codex cheatsheet](https://littlebearapps.com/help/untether/exec-json-cheatsheet), retrieved 2026-10-16. Read every field defensively.

**Q5. Multi-machine consistency.**
Redis is shared, and so are the claims: `live/claims.rb:1-9` says the claim rule is advisory and lapses within `CLAIM_TTL = 90` (`live/keys.rb:183`). Keys are namespaced per repo (`live/keys.rb:19`) and per node (`live/keys.rb:63`). A JSONL file per node has no cross-node write conflict, because each file has one writer. Aggregates then merge the files at read time, deduped by `event_id`. Document that: events from a node that is offline appear late, and nothing is ever rewritten. A single shared PostgreSQL is the only option that needs a real consistency rule (an insert unique on `event_id`).

**Q6. Retention and redaction.**
Nothing in `lib/` redacts or expires anything. Recommendation: store ids, timestamps, adapter, model, usage, outcome and error class only. Never store prompts, transcripts or agent text. Raw traces stay in `Dir.tmpdir/openlanes-traces` (`CLAUDE.md`), outside the sink.

### Contradictions

1. **Run state location.** This plan cites `live/run_record.rb` as the precedent for a file copy in `.plans/openlanes-state.json`. Plan 021.00 (`runtime-state-outside-plans`) says that file must move out of `.plans/`. The sink must follow whatever 021.00 decides, not the current path.
2. **Cost on codex and pi.** `live/meter.rb` shows spend as `$0` for an unpriced model. `adapters/claude.rb` says an unnamed model "is still priced rather than shown as free", so the code and its own rule disagree for the other two adapters.
3. **Cache accounting differs by adapter.** `execution/transcript.rb:344` adds cache creation and cache read to input tokens; `adapters/stream.rb:151-153` does not. So the same `up` field means different things per adapter, and the sink must not sum them across adapters without a note.
4. **Plan 022.00 (Redis outage resilience)** says the engine should pause and retry when Redis drops. A durable sink that writes through Redis would stop with it. Write the sink independently of Redis.

### Not settled

1. Whether the owner wants PostgreSQL as the chosen deployment, or only an option (the issue says "if that is the chosen deployment path").
2. Which exact Claude `total_cost_usd` semantics hold for the CLI version this repo pins. Needs one real run with `--output-format stream-json` to check.
3. Codex and pi usage field names for the versions installed on this machine. Needs one real run of each.
4. The location of the sink, which depends on plan 021.00.
5. Whether `estimated: true` should be a column or only a label on the aggregate report. A product choice, not a research one.
6. Whether block-to-unique-run counts treat a re-block after a human answer as a new run. The answer is in `docs/decisions/decisions-on-blocks-and-escalation.md`, which was not read in full.

### Findings, Conclusion & References

Findings: no event model or durable sink exists. The views in `web/` and `live/` are not records. The one durable precedent is the run-state file mirror, and it sits in the wrong place. Claude usage can be trusted from the `result` event. Codex and pi usage is partial, and their cost is unpriced and shows as zero.

Conclusion: build an append-only JSONL event sink, one file per node, outside the repo, keyed by a hash of node, checkout, plan, round, agent and invocation start. Store ids, timestamps and usage, with cost marked as an estimate. Make it optional with a config flag. Settle the file location with plan 021.00 first.

References:
- Repo: `web/events.rb:1-30`, `live/subscriber.rb:1-20`, `live/run_record.rb:1-40`, `live/meter.rb:1-47`, `live/claims.rb:1-9`, `live/node.rb:1-20`, `live/keys.rb:19,63,183`, `execution/transcript.rb:327-348,422-433,502-512`, `adapters/stream.rb:148-153`, `adapters/claude.rb:12-40`, `adapters/base.rb:44`, `adapters/model.rb:25`, `gemspec:58-89`.
- Plan 021.00 `.plans/021.00━━🔎━━❯runtime-state-outside-plans/spec.md`, plan 022.00 `.plans/022.00━━🟡━━❯redis-outage-resilience/spec.md`.
- Web, retrieved 2026-10-16: [claudeissues 83239](https://claudeissues.com/issue/83239-docs-total-cost-usd-is-cumulative-per-session-under-output-format-stream-json-bu), [claudeissues 53371](https://claudeissues.com/issue/53371-total-cost-usd-returns-incorrect-values-10x-too-high), [littlebearapps codex cheatsheet](https://littlebearapps.com/help/untether/exec-json-cheatsheet). These are third-party; the official schema pages were not reached.

## Framing

Two ways to frame the problem:

1. **Reporting problem.** Product questions (block rate, PR outcome, cost per model) need aggregate queries, so choose a queryable store first (SQLite or PostgreSQL) and derive events from it.
2. **Record-keeping problem.** Nothing durable records what happened; once a run ends or Redis is flushed the facts are gone (Research Q1: no existing stream is a source of record). Fix the record first: an append-only, idempotent event log. Queries read the log.

**Chosen: 2.** The log needs no new dependency (Research Q2, `gemspec:58-89`), has one writer per file (Research Q5), and any later store (SQLite, PostgreSQL) can be loaded from it without losing history.

## Goal

After this ships, a single-machine install can opt in to a durable, append-only log of run, agent, block/answer and PR lifecycle events, and `openlanes` can answer from that log how often agents complete, how often they needed a human, how long answers took, what happened to the PRs, and what usage each run or model cost. Nothing in the log contains source code, prompts or conversation text.

## Non-Goals

- Replacing Redis or changing live coordination (claims, snapshots, pub/sub).
- A dashboard, web page or chart for the metrics. A CLI report is enough.
- Storing prompts, transcripts, agent text or code. Raw traces stay in `Dir.tmpdir/openlanes-traces`.
- Billing-grade cost accuracy. Cost is an estimate unless a provider reports it.
- Shipping a PostgreSQL backend in this plan (see Out of scope).
- Back-filling events for runs that happened before the sink existed.

## In scope

Each item has a check.

1. **Event model.** A value type (`Data.define`) with `event_id`, `kind`, `at`, `project`, `plan`, `run`, `agent`, `adapter`, `model`, and a kind-specific payload. Check: spec builds each kind and asserts the fields.
2. **Kinds:** run start/finish, agent start/finish, block raised, human answered, PR opened/reviewed/merged/closed, failure (with error class only). Check: a spec per kind, driven by a real `.plans` tree via `PlansFixture`.
3. **Idempotent identity.** `event_id` is a digest of node, checkout, plan, round, agent, invocation start, kind and seq (Research Q3). Check: emitting the same invocation twice yields one event after read-time dedupe.
4. **Sink.** Append-only JSONL, one file per node, outside the repo; a no-op sink when disabled. Check: a spec writes events, reads them back, and confirms no write when disabled.
5. **Optional persistence.** Off by default for a single-machine install; enabled by a `.openlanes.yml` key. Check: with the key absent, no file is created.
6. **Independent of Redis.** Writes never go through Redis and a Redis error never fails an emit (Research contradiction 4). Check: a spec with a failing store still writes the event.
7. **Block metrics.** The report separates block count from the number of unique agent runs that needed feedback. Check: a fixture with 3 blocks over 2 runs reports 3 and 2.
8. **Usage.** Record provider-reported tokens when present; cost carries `estimated: true`; codex and pi cost is `null`, never `0` (Research Q4). Check: a spec per adapter, plus a claude spec that a sub-agent run is flagged incomplete.
9. **Aggregates.** CLI report: completion rate, intervention rate, time-to-answer, PR outcome, usage by run and by model, merged across node files and deduped by `event_id`. Check: a fixture of two node files with one duplicate gives the expected numbers.
10. **Redaction by construction.** The event type has no free-text field except a bounded `error_class`. Check: a spec asserts the key set of every serialised kind against an allowlist.
11. **Docs.** Multi-machine behaviour documented: one writer per file, late arrival from offline nodes, nothing rewritten. Check: `openlanes docs` or README section exists and names these three points.

## Out of scope

| Item | Reason |
| :--- | :--- |
| PostgreSQL backend | The issue says "if that is the chosen deployment path"; the owner has not chosen it (Research, not settled 1). The JSONL log is loadable into it later. |
| SQLite backend | No dependency today; revisit when JSONL aggregates get slow (Research Q2). |
| Storing `total_cost_usd` | Semantics unverified and third-party reports conflict (Research Q4). |
| Retention and expiry jobs | Nothing in `lib/` expires anything; the log is small and ids-only. Revisit with real sizes. |
| Moving run state out of `.plans/` | That is plan 021.00. |
| Redis outage handling | That is plan 022.00. |

## Back end / front end

- **Back end (`luke-backend`):** items 1 to 10: event type, emit points in `engine/dispatcher.rb` and `live/run_record.rb`, sink, config key, usage mapping, aggregates, `vcs/github.rb` for PR facts.
- **Front end (`rey-frontend`):** the CLI report for item 9 (command, table output on STDERR/STDOUT per the repo convention, `-o` output), and the config and docs text of items 5 and 11. No web UI.
- Pair contract: luke exposes an aggregate result value; rey renders it. Agree the field names in the mailbox before coding.

## Open questions

Assumed in this spec; each is overridable before planning:

1. **PostgreSQL:** assumed optional and later (Research, not settled 1).
2. **Sink location:** depends on 021.00. Assumed a configurable directory with a default outside `.plans/`; palpatine should read 021.00's decision first (not settled 4).
3. **`total_cost_usd`:** not stored; needs one real stream-json run to settle (not settled 2).
4. **Codex and pi usage field names:** read defensively, as null when absent; needs one real run each (not settled 3).
5. **`estimated` as column or report label:** assumed a per-event field, which is the safer superset (not settled 5).
6. **Re-block after an answer:** `docs/decisions/decisions-on-blocks-and-escalation.md` (read in full, 81 lines) does not say whether it is a new run. Assumed it is the same unique run (keyed by plan, round, agent) and a new block.
7. **Numbering:** the folder is `020.01` with no `pull-requests.md` and no event code in `lib/`, so this is treated as new work, not a retroactive plan.
8. **PostgreSQL class** (`PG-lax`/`strict`/`analytics`) is not in `CLAUDE.md`; matters only if item 1 flips.
9. **Per-adapter cache accounting** differs (Research contradiction 3); assumed the report labels usage per adapter and does not sum across adapters.

## Risks to planning or execution

- 021.00 may change where run state lives; sink path work could be redone. Mitigate: one path-resolver method.
- Emit points in `engine/dispatcher.rb` are on the hot tick loop; a slow or failing write must not stall or fail a run. Mitigate: rescue and log, never raise.
- Concurrent worktrees on one machine share a node id; `checkout_id` in the key keeps them distinct, but two processes appending to one file need an atomic single-line `O_APPEND` write.
- Usage semantics are unverified for codex and pi, so tests cover shape only.
- Plan 022.00 touches the same engine and Redis seams; merge conflicts likely.

## Conclusion

When this ships, an opt-in append-only JSONL log per node records idempotent plan, run, agent, block/answer and PR events with ids, timestamps, adapter, model and usage, and no text content. A CLI report merges the node files and reports completion rate, intervention rate (blocks versus unique runs), time-to-answer, PR outcome and estimated usage by run and model. Redis stays the live store and is never on the write path.
