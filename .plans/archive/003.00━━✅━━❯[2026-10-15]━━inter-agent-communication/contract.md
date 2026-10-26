# Implementation plan: the contract between backend-coder and frontend-coder

Owner: `backend-coder`. Renamed from `implementation-plan.md` by B5 (this folder only; older folders keep their names).

## Baseline

`bundle exec rspec` on the branch before any change: see the line below, filled in when the run finished.

- Baseline: `2214 examples, 0 failures`, coverage 98.64%. No pre-existing failures.

## Interfaces frontend-coder calls

All Ruby, no HTTP. Every method below reads; none writes unless it says so.

### B1. `OpenLanes::Plans::Mailbox`

| Method | Input | Returns | Errors |
| :-- | :-- | :-- | :-- |
| `Mailbox#messages` | none | `Array<Mailbox::Message>`; `Message` gains `read` (`"yes"` or `"no"`) and `read?` | none |
| `Mailbox#unacked(recipient = nil)` (amended: `for` is a Ruby keyword, so the reader is positional) | optional agent name | `Integer`, messages with `read == "no"` (a legacy message with no key counts as `"no"`; a `mailbox.md` message counts as read, it predates acking) | none |
| `Mailbox#ack(number, by:)` | message number, the reader's name | the acked `Message`; writes `state.json` under the plan lock. Already read: no-op, returns it | `OpenLanes::Error` on an unknown number, or when `by` is not the recipient |
| `Mailbox#render` | none | `String`, Markdown of the whole exchange, one `## N · at · from → to` heading per message with `(read)` / `(unread)`. Prints nothing | none |

CLI: `openlanes mail ack --plan N --for AGENT NUMBER` (exit 65 on unknown number), `openlanes mail render --plan N` (STDOUT only, writes nothing).

### B2. `OpenLanes::Plans::PlanState`, `last-known-state`

| Method | Input | Returns | Errors |
| :-- | :-- | :-- | :-- |
| `PlanState#record_last_known(agent, entry)` | agent name, `Plans::LastKnownState` | the entry kept (may be the existing one when precedence refuses the new) | `OpenLanes::Error` on a bad agent name |
| `PlanState#last_known(agent)` | agent name | `Plans::LastKnownState` or `nil` | none |
| `PlanState#last_known_states` | none | `Hash{String => Plans::LastKnownState}`, empty when the section is absent | none |

`Plans::LastKnownState = Data.define(:source, :at, :round, :status, :done, :remaining, :next_step, :files_touched, :note)`; `source` is `"agent"` or `"harness"`; arrays default to `[]`, strings to `nil`. Stored in `state.json` under `"last-known-state"`, keyed by agent.

Precedence: an agent entry replaces anything; a harness entry never replaces an agent entry of the same or a later round.

CLI: `openlanes state resume --plan N --agent A --round R --status S [--done X,Y] [--remaining X,Y] [--next-step TEXT] [--files A,B] [--note TEXT]`.

## File ownership

| Files | Owner |
| :-- | :-- |
| `lib/openlanes/plans/*`, `schemas/*`, `lib/openlanes/cli/mail/*`, `lib/openlanes/cli/state/*`, `lib/openlanes/cli.rb`, `lib/openlanes/live/*`, `lib/openlanes/engine/dispatcher.rb`, `agents/*.md`, `lib/openlanes/execution/*`, `lib/openlanes/presentation/*`, `lib/openlanes/agents/*` | backend-coder |
| `lib/openlanes/engine/board*`, `lib/openlanes/web*`, web templates, `spec/openlanes/engine/board/*`, `spec/openlanes/web/*`, `spec/integration/mail_round_trip_spec.rb` | frontend-coder |

Shared: none written by both. `lib/openlanes/web.rb:25` file list is frontend-coder's (F1), including the `contract.md` rename.

## Build order

B1 → B2 → (B3, B5, B6) → B4. F1 may start once B1 and B2 are marked landed in the mailbox. F2 last.

## Integration proof

`spec/integration/mail_round_trip_spec.rb` (frontend-coder, F2): real `:tree` plan, real CLI commands, real `Board` and web app; send → one unacked → ack → zero → render leaves folder unchanged.

## Known gaps

- D8 option (c): hand edits to `plan.md` checkboxes take no lock.
- `rg implementation-plan lib agents` is not empty: the agent prompts name the legacy files so older folders keep working (decision D3).

## Progress

- [x] B1
- [x] B2
- [x] B3
- [x] B4
- [x] B5
- [x] B6
- [x] F1
- [x] F2

## Snapshot wire (amended: added for frontend-coder's blocked.md B1, option 1)

`Live::Snapshot#plan` gains `unacked: Integer` and `last_known: [{agent, source, at, round, status, next_step, note}]` (empty array when none). `web/src/api/fixtures/snapshot.json` updated to match (frontend-coder's file; mailed as #5). `web/src/api/types.ts` and the panel are frontend-coder's, not done.

## Resume (round 1 interrupted)

- Done: B1, B2, the snapshot wire above. Specs green for mailbox, plan_state, last_known_state, cli/mail, cli/state, live/snapshot.
- Not done: B3, B4, B5, B6; a full-suite run and a full `rubocop` after the snapshot change.
- Next step: `bundle exec rspec && bundle exec rubocop` in the worktree, then B3 (`Live::Mail`).

## B3 and B4 (round 1, after the compaction)

- B3 done: one mail stream per checkout, `openlanes:<repo>:<node>:<checkout>:mail`, plan inside each entry; one consumer group per plan (`mail:<ordinal>`), so a plan's drain never takes another plan's mail. Each publish trims by exact MINID to one hour and renews a one-hour expiry. `mail send` writes `state.json` first, publishes to the plans directory's checkout (not the sender's worktree), and is silent when Redis is unavailable. Store seam gained `xtrim(key, minid:)`, also as a MULTI write, in both stores and the shared examples.
- B4 done. Open question 4 answered: no mail drain existed; `Live::Subscriber` is plan 006's pub/sub chat only. The drain runs once per tick, once per plan with an agent running, consumer `harness`.
- Amended (B4 needed it, outside its listed files): `PlanState#deliver!` and `Mailbox#deliver` keep a drained message under its own number, skip a number already present (no write at all, so mtime holds), and always store it unread. `Live::Session#attach` sets `dispatcher.mail`, one line.
- Harness resume record is written wherever the harness writes an Interrupted line or sees the agent die: stranded stage, discard/fence stop, kill or timeout without the work on disk, non-zero exit, executor raise. Note = reason, last ledger line (read before the harness's own line), last transcript phrase. Not written when the harness signs Completed for verified work.

## Resume (round 1, STOP after B4)

- Checks at STOP: affected suites 778 examples, 0 failures; `rubocop lib spec` clean. Full `bundle exec rspec` last run green before B3 (2251, 0 failures); rerun it first.
- Next: B5 (plan.md units, `contract.md` rename, prompts ask for `mail ack` and `state resume`), then B6.

## B5, B6, F1, F2 (finishing session, 2026-10-14)

- Salvaged the uncommitted round-1 work as five commits, rebased on `origin/main` (no conflicts).
- B5 done. `planner` writes `## Backend`, `## Frontend` and `## HTTP surface` inside `plan.md`. `frontend-coder` declares `needs: ["plan.md#frontend"]`: `Routing.units?` reads `file#section` as the `###` headings under that `##`, and falls back to `plan-<section>.md` when `plan.md` has no such section, so no folder migrates. `backend-coder` and `frontend-coder` ledgers are `[plan.md, pull-requests.md, plan-<half>.md]`. Prompts ask for `mail ack` after each read and for `state resume` on INTERRUPT; the RESUME mail survives only as the human's note from the page (`Live::Commands`). `openlanes docs`, `docs/WORKFLOW.md` and the `openlanes-documents` skill name `contract.md` and `openapi.yaml`.
- B6 done. `Presentation::ApiDocs#call(tree)` and `openlanes api docs`: found files on STDOUT with an `npx @redocly/cli build-docs` line, problems on STDERR as `path: reason`, exit 65 when any file is bad.
- F1 done (decisions D1, D2). `Board::Row#unacked`, filled in `Dispatcher#row_for` through `Board::Row.unacked_in`; `UnackedBadge` on the plan row; `LastKnownTable` in the agent drawer. Snapshot key is `last_known` (amended: D1 said `last_known_state`; the shorter key shipped with B2 and the page reads it).
- F2 done: `spec/integration/mail_round_trip_spec.rb`.

## Review fixes (Grok on PR 28, 2026-10-14)

- Amends B4: a drained message is deduped by identity, not number. `mail send` writes an `id` (UUID) into each message (schema updated); `PlanState#deliver!` matches on `id` when both sides have one, else on from, to, at and body. A different message whose number is taken (a worktree's `state.json` numbers independently) is kept under the next free number. `mailbox.md` messages are matched by content too.
- Amends B3/B4: `Live::Mail#drain` acks an entry only after the dispatcher kept it; one whose plan this checkout cannot find stays pending and is retried each tick. An invalid message is acked and logged, since a retry cannot make it valid.
- Amends B4: the drain covers every plan the stream has mail for (`Live::Mail#plans_since`, a cursor from "0" at startup), not only plans with an agent running, so a worktree's message is kept before the one-hour trim.
- `mail ack` on a `mailbox.md` number says it is a legacy message and that nothing was written.
