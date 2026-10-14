# Implementation plan: the contract between luke-backend and rey-frontend

Owner: `luke-backend`. Renamed to `contract.md` by B5; until B5 lands it lives here.

## Baseline

`bundle exec rspec` on the branch before any change: see the line below, filled in when the run finished.

- Baseline: `2214 examples, 0 failures`, coverage 98.64%. No pre-existing failures.

## Interfaces rey calls

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
| `lib/openlanes/plans/*`, `schemas/*`, `lib/openlanes/cli/mail/*`, `lib/openlanes/cli/state/*`, `lib/openlanes/cli.rb`, `lib/openlanes/live/*`, `lib/openlanes/engine/dispatcher.rb`, `agents/*.md`, `lib/openlanes/execution/*`, `lib/openlanes/presentation/*`, `lib/openlanes/agents/*` | luke |
| `lib/openlanes/engine/board*`, `lib/openlanes/web*`, web templates, `spec/openlanes/engine/board/*`, `spec/openlanes/web/*`, `spec/integration/mail_round_trip_spec.rb` | rey |

Shared: none written by both. `lib/openlanes/web.rb:25` file list is rey's (F1), including the `contract.md` rename.

## Build order

B1 → B2 → (B3, B5, B6) → B4. F1 may start once B1 and B2 are marked landed in the mailbox. F2 last.

## Integration proof

`spec/integration/mail_round_trip_spec.rb` (rey, F2): real `:tree` plan, real CLI commands, real `Board` and web app; send → one unacked → ack → zero → render leaves folder unchanged.

## Known gaps

- D8 option (c): hand edits to `plan.md` checkboxes take no lock.

## Progress

- [x] B1
- [x] B2
- [x] B3
- [x] B4
- [ ] B5
- [ ] B6

## Snapshot wire (amended: added for rey's blocked.md B1, option 1)

`Live::Snapshot#plan` gains `unacked: Integer` and `last_known: [{agent, source, at, round, status, next_step, note}]` (empty array when none). `web/src/api/fixtures/snapshot.json` updated to match (rey's file; mailed as #5). `web/src/api/types.ts` and the panel are rey's, not done.

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
