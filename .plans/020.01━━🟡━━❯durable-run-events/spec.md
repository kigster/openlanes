---
created: 2026-10-16
starts: research
---

# Durable Run Events

> [!NOTE]
> **Written retroactively on 2026-10-23.** This documents work built on branch
> `kig/020.01-durable-run-events` and carried by #105 (open at the time of writing,
> see `pull-requests.md`). It describes what exists in that branch; it does not
> record a decision taken in advance.

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

## Research

Method: read the code the feature touches; no test run was needed for these answers. Two web searches, dated 2026-10-16, for the provider output formats the repo does not document.

### Answers

**Q1. Can an existing stream be persisted instead of a new model?**
No. `web/events.rb:1-30` is a polled SSE view of Redis snapshots, replies, chat and copilot turns. It keeps no history and drops nothing into storage. `live/subscriber.rb:1-20` is a Redis pub/sub connection, so messages not read are lost. Neither is a source of record. Build the event model from the engine's own transitions (`engine/dispatcher.rb`, `live/run_record.rb:39`), not from the view layer.

**Q2. Which sink on one machine?**
An ActiveRecord-based recording system compatible with any database, but especially SQLite for solo-machine developers or PostgreSQL for distributed use. 

Use AR migrations, create the database "openlanes_development," and create the initial table `events` (append-only).

Create an agents table, including their Markdown description imported from the file system. 

Create a table for "plans" that contains plan's ID (but a UUIDv7 primary key) and the title, but no state emoji in the title.

Create a tasks table for plans that are "in flight". This can be populated by events (use pub/sub model) initially. 

**Q3. Idempotency key.**
Recommendation: `event_id = sha256(node_id, checkout_id, ordinal, round, agent, invocation_start, kind, seq)`. Evidence: `Live::Meter` already keys one invocation by `[agent, round, since]` (`live/meter.rb:1-20`, `since` on `engine/board.rb:53`); `Live::Node` gives `id` (digest of `user@host`) and `checkout_id` (`live/node.rb:1-20`); `RunState#seq` is monotonic only inside one node (`live/run_state.rb:21,50,62`), so it cannot be a global key. Replaying the same invocation must produce the same `event_id`, so a duplicate write is a no-op on a unique index or a line-level dedupe at read time.

**Q4. Reliable usage per adapter.**
- `claude`: reliable. The `result` event's `usage` is the invocation's final accounting and replaces the running total (`execution/transcript.rb:430-433`, `502-512`). Only `message_delta` is trusted mid-stream; `assistant` output tokens are placeholders (`transcript.rb:327-348`). Sub-agent spend is left out of the `result` figure (`transcript.rb:422-429`), so label it incomplete when `subagent_stats.spawned > 0`.
- `codex`: partial. `adapters/stream.rb:148-153` adds `input_tokens`/`output_tokens` per event and does not add `cached_input_tokens` to the total. Codex prices nothing: `adapters/codex.rb` has no `models`, and `adapters/base.rb:44` returns `[]`. So `Meter#for` (`live/meter.rb:43-47`) prices every codex spend at `0`, which reads as free. Store codex cost as unknown (`null`), not `0`.
- `pi`: same as codex. No model table (`adapters/pi.rb`, `base.rb:44`), and usage is read by shape, so it is unverified.
- Estimates: `Model#cost` (`adapters/model.rb:25`) ignores cache reads and cache writes, which the Claude table itself flags (`adapters/claude.rb:18-22`). Every cost computed here is an estimate and must carry `estimated: true`. Provider-reported cost (`total_cost_usd`) is not read anywhere in `lib/`. Third-party reports disagree on whether `total_cost_usd` is per call or cumulative per session under stream-json, and one reports a 10× overstatement, so do not store it without checking against real output: [claudeissues 83239](https://claudeissues.com/issue/83239-docs-total-cost-usd-is-cumulative-per-session-under-output-format-stream-json-bu), [claudeissues 53371](https://claudeissues.com/issue/53371-total-cost-usd-returns-incorrect-values-10x-too-high), both retrieved 2026-10-16. Codex `turn.completed` carries `input_tokens`, `cached_input_tokens`, `output_tokens`, but the field set varies by Codex version: [littlebearapps codex cheatsheet](https://littlebearapps.com/help/untether/exec-json-cheatsheet), retrieved 2026-10-16. Read every field defensively.

**Q5. Retention and redaction.**
Nothing in `lib/` redacts or expires anything. Recommendation: store only IDs, timestamps, adapter, model, usage, outcome, and error class. Never store prompts, transcripts, or agent text except agent's definition. Raw traces stay in `Dir.tmpdir/openlanes-traces` (`CLAUDE.md`), outside the sink.

## Framings

1. **Event log first.** An append-only, node-local file of immutable events; reports are folds over it. Cheap, no server, idempotent by key, merges across machines by file union.
2. **Database first.** ActiveRecord tables (`events`, `agents`, `plans`, `tasks`) on SQLite or PostgreSQL, as Research Q2 sketches; the UI reads from it and live state migrates out of Redis over time.

Picked: **1** for this plan. The branch implements it (`lib/openlanes/events/{event,sink,log,report}.rb`), it meets "optional for a single-machine install" with no dependency, and a database can later be loaded from the same events. Framing 2 stays an open question (Q1) because Research Q2 and the Goal addendum ask for it.

## Goal 

After this ships, a single-machine install can opt in to a durable, append-only log of run, agent, block/answer and PR lifecycle events, and `openlanes` can answer from that log how often agents complete, how often they needed a human, how long answers took, what happened to the PRs, and what usage each run or model cost. Nothing in the log contains source code, prompts, or conversation text.

However, the UI can begin to use PostgreSQL for display purposes, and some functionality will later begin migrating out of redis.

Produce a nav button that swaps the page to a reports URL, which shows the reports that can be generated via CLI and through the same classes shown on the UI. If we have any shadcn components to show the data visually, please do so.

Board and Reports are separate  pages, and loading one closes the other.

## Non-Goals

- Completely replacing Redis or changing live coordination (claims, snapshots, pub/sub).
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

- **ActiveRecord/SQLite/PostgreSQL sink, `agents`/`plans`/`tasks` tables** (Research Q2). Why: contradicts the JSONL sink in In scope item 4 and adds a database dependency to a single-machine install. See Q1.
- **UI reading from PostgreSQL, Board/Reports pages, nav button, shadcn charts** (Goal addendum). Why: no front-end work exists in the branch diff (`git diff --stat main...HEAD` touches no `web/`), and it depends on a database sink. See Q1 and Q2.
- **Provider-reported cost (`total_cost_usd`).** Why: Research Q4 says sources disagree on per-call vs cumulative; not read anywhere in `lib/`.
- **Retention or expiry of event files.** Why: nothing expires today (Research Q5); events hold no free text, so the cost of keeping them is low.
- **Back-filling past runs.** Why: Non-Goal; no source holds the data.

## Back end / front end

Every In scope item (1-11) is back end (`luke-backend`): `lib/openlanes/events/*`, `engine/*` emit points, `support/config.rb`, `cli/events/subcommands/report.rb`, `docs/events.md`. The only presentation piece is the terminal renderer `presentation/events_report.rb`, also back end (a string-returning renderer, STDOUT is the deliverable).

Front end (`rey-frontend`): nothing in scope. The Reports page and nav button are out of scope pending Q2; `rey-frontend`'s role here is the integration proof (subprocess run of `events report`, recorded in `pull-requests.md`).

## Decisions

### B1 (answered) — Sink: JSONL or ActiveRecord with a Reports page?

Research Q2 asks for an ActiveRecord sink (`events`, `agents`, `plans`, `tasks`; SQLite or PostgreSQL), a nav button and a web Reports page. The branch ships an append-only JSONL sink and the `openlanes events report` CLI. Options offered: (a) JSONL stays, the CLI is the whole front end; (b) build the AR/PostgreSQL sink plus the nav button and Reports page; (c) JSONL now, AR and Reports as plan 020.02.

### D1 (decision) — Build the database sink and the Reports page

Answered:

- 2026-10-23
- By kig

Option (b) is chosen. The plan delivers an ActiveRecord sink on SQLite or PostgreSQL with the `events`, `agents`, `plans` and `tasks` tables, a nav button, and a web Reports page. The Reports page shows the reports that the CLI generates, through the same classes. Board and Reports are separate pages; loading one closes the other. This is the largest of the three options and adds a dependency, migrations and web work. Supersedes the JSONL-only scope in In scope item 4 and the Out of scope entries for the database and front end.

## Open questions

1. **Q1. Sink: JSONL or database?** Research Q2 and the Goal addendum ask for ActiveRecord with SQLite/PostgreSQL; In scope item 4 and the branch ship JSONL. Assumed: JSONL now, database later as a consumer of the same events. Needs a human decision (product).
2. **Q2. Reports page in the web UI.** Asked for in the Goal addendum, not built, not in this scope. Assumed: a follow-up plan after Q1.
3. **Q3. Research cites "contradiction 4"** (In scope item 6) but `## Research` has no list of contradictions; it is unanchored. Assumed: it means "Redis must not be on the write path", which Q1/Q3 of Research support.
4. **Q4. `total_cost_usd`.** Check real `claude` stream-json output before ever storing it (Research Q4).
5. **Q5. Codex and pi usage fields** vary by version; read defensively. Which pi fields are reliable is unverified.
6. **Q6. Event file location and rotation.** Assumed: outside the repo, one file per node (item 4); `events/location.rb` holds the rule and was not re-verified here.
7. **Q7. Leah's unsettled list** (Research "What research needs to settle"): sink choice (Q1), idempotency key (answered, Research Q3), per-adapter usage (Q4/Q5), multi-machine consistency (answered by one-writer-per-file, item 11), retention (out of scope).

## Risks to planning or execution

- The spec, Research Q2 and the Goal addendum disagree about the sink; planners could split work around the database that is not built. Mitigation: Out of scope names it.
- Code is already built and verified in three rounds (`verification/`), so a planner may over-plan; units should be limited to gaps against the items above.
- Codex/pi cost recorded as `0` would read as free; item 8 guards it.
- `event_id` includes `seq`, which is monotonic only per node (Research Q3); a change to what feeds the digest silently breaks dedupe across nodes.
- Full suite passed only after applying main's port-detection fix by hand (`pull-requests.md`, luke round 1); a rebase may conflict.

## Conclusion

When this ships, an install can set a `.openlanes.yml` key and get an append-only JSONL log per node recording run, agent, block/answer, PR and failure events with stable `event_id`s and no free text. `openlanes events report` merges node files, dedupes, and prints completion and intervention rates, time-to-answer, PR outcomes and usage by run and model, with costs labelled as estimates and `null` where unknown. `docs/events.md` explains multi-machine behaviour. A database sink and a web Reports page do not exist and wait on Q1.
