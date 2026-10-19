# Plan: back end (`luke-backend`)

Order and the dependency graph are in `plan.md`. Names follow the code (`openlanes`, `Live::Keys`), not the spec's older `agentilda` text. Where the spec's decisions and its "Tightening from the research" table disagree, the table wins.

## B1. Read receipt, `mail ack`, `mail render`, unacked count

- **Discipline:** back end
- **Owns:** `lib/openlanes/plans/mailbox.rb`, `lib/openlanes/plans/plan_state.rb` (the `messages` part), `schemas/plan-state.schema.json` (the `read` field), `lib/openlanes/cli/mail/subcommands/ack.rb` (new), `lib/openlanes/cli/mail/subcommands/render.rb` (new), the `mail` registration in `lib/openlanes/cli.rb`, `spec/openlanes/plans/mailbox_spec.rb`, `spec/openlanes/cli/mail/ack_spec.rb` (new), `spec/openlanes/cli/mail/render_spec.rb` (new)
- **Must not touch:** `lib/openlanes/engine/*`, `lib/openlanes/web*`, `lib/openlanes/live/*`, `agents/*.md`, `lib/openlanes/cli/mail/subcommands/send.rb`
- **Depends on:** nothing
- **Shape:**
  - each message gains `read`, `"no"` on append, `"yes"` after ack; a message with no `read` key (written before this change) reads as `"no"`. Field addition only, no schema `version` bump.
  - `Mailbox#ack(number, by:)` writes through `PlanState`'s locked path (`openlanes-plan-<key>.lock`), never a bare file write.
  - `Mailbox#unacked(for: nil)` returns the count, optionally for one recipient. B4 and F1 read it.
  - `Mailbox#render` returns the whole exchange as Markdown, prints nothing.
  - `openlanes mail ack --dir D --plan N --for AGENT NUMBER` (one message by its number; acking an already-read message is a no-op, an unknown number exits non-zero). `openlanes mail render --dir D --plan N` prints to STDOUT and writes no file.
- **Done when:** `spec/openlanes/plans/mailbox_spec.rb` asserts a new message has `read: "no"`, ack flips only the named one, and a legacy message without `read` counts as unacked; `spec/openlanes/cli/mail/ack_spec.rb` (`:tree`) asserts two concurrent acks from two threads both land; `spec/openlanes/cli/mail/render_spec.rb` asserts STDOUT content and an unchanged plan folder (file list and mtimes).

## B2. `last-known-state` in `state.json`

- **Discipline:** back end
- **Owns:** `lib/openlanes/plans/plan_state.rb` (the new section), `lib/openlanes/plans/last_known_state.rb` (new, a `Data.define` value with `source`, `at`, `round`, `status`, `done`, `remaining`, `next_step`, `files_touched`, `note`), `schemas/plan-state.schema.json` (the new section), `lib/openlanes/cli/state/subcommands/resume.rb` (new: `openlanes state resume --plan N --agent A --status S --done ... --remaining ... --next-step ... --files ...`, the agent's writer), `spec/openlanes/plans/last_known_state_spec.rb` (new), `spec/openlanes/plans/plan_state_spec.rb`, `spec/openlanes/cli/state/resume_spec.rb` (new), the `state resume` registration in `lib/openlanes/cli.rb`
- **Must not touch:** `lib/openlanes/plans/mailbox.rb`, `lib/openlanes/engine/*`, `lib/openlanes/web*`
- **Depends on:** B1 (both write `plan_state.rb` and the schema: sequential)
- **Shape:**
  - `PlanState#record_last_known(agent, entry)`, under the plan lock. Keyed by agent name, last entry wins, so rounds do not accumulate.
  - Precedence: a `source: "harness"` entry never replaces a `source: "agent"` entry of the same or a later round. An agent entry replaces anything.
  - `PlanState#last_known(agent)` and `#last_known_states` for readers (B4, F1).
  - Schema: both shapes validate; the section is optional, so old folders still validate. No pid, token or exit-code field exists in the schema at all (`additionalProperties: false`), which is how "machine detail stays out of the committed file" is enforced.
- **Done when:** `spec/openlanes/plans/last_known_state_spec.rb` covers precedence both ways and same-agent replacement across rounds; `spec/openlanes/plans/plan_state_spec.rb` validates both shapes against `schemas/plan-state.schema.json` and rejects an entry carrying `pid`, `tokens` or `exit`; `spec/openlanes/cli/state/resume_spec.rb` writes an agent entry through the CLI.

## B3. Optional Redis transport for mail

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/keys.rb` (a mail stream key), `lib/openlanes/live/mail.rb` (new: `Live::Mail#publish(plan:, message:)`, `#drain(plan:, consumer:)` returning messages and acking delivery), `lib/openlanes/live/store.rb`, `lib/openlanes/live/memory_store.rb` (any stream primitives `Live::Mail` needs that the seam lacks), `lib/openlanes/cli/mail/subcommands/send.rb`, `spec/openlanes/live/store_examples.rb`, `spec/openlanes/live/mail_spec.rb` (new), `spec/openlanes/cli/mail/send_spec.rb`
- **Must not touch:** `lib/openlanes/engine/*`, `lib/openlanes/plans/*`, `lib/openlanes/engine/runner.rb` (the degraded `claim` path stays as is)
- **Depends on:** B1 (the message shape, including `read`)
- **Shape:**
  - Key layout follows the code and W26: `openlanes:<repo>:<node>:<checkout>:mail`, the plan carried inside the message, not in the key.
  - Streams with a consumer group, not pub/sub. Each write `XTRIM ... MINID <now - 60min>` and `EXPIRE`s the key.
  - `mail send` always writes `state.json` first, then publishes when `Live.connect` succeeds. `Live::Unavailable` is swallowed for mail: no error, no warning on STDOUT, the send still succeeds.
- **Done when:** `spec/openlanes/live/store_examples.rb` gains the stream behaviour and passes against both `Live::Store` and `Live::MemoryStore`; `spec/openlanes/live/mail_spec.rb` covers publish, drain, trim; `spec/openlanes/cli/mail/send_spec.rb` raises `Live::Unavailable` from the connect seam and still finds the message in `state.json`.

## B4. Harness thread as writer: drained mail and the fallback resume record

- **Discipline:** back end
- **Owns:** `lib/openlanes/engine/dispatcher.rb`, `spec/openlanes/engine/dispatcher_mail_spec.rb` (new), `spec/openlanes/engine/dispatcher_last_known_state_spec.rb` (new)
- **Must not touch:** `lib/openlanes/plans/*`, `lib/openlanes/live/*`, `lib/openlanes/engine/board.rb`, `lib/openlanes/engine/runner.rb`
- **Depends on:** B2, B3
- **Shape:**
  - The per-agent thread (the one around `child.each_chunk`, beside the `Clock`) drains `Live::Mail` once a second and writes any message not already in `state.json` (dedupe by message number) through `Mailbox`, under the plan lock. With no Redis it drains nothing; `state.json` is already written by `mail send`.
  - First task: trace whether such a drain exists today through `Live::Subscriber` (open question 4). If one does, extend it rather than adding a second loop.
  - On interrupt, `GRACE` expiry or harness-observed death, with no agent entry for this round, write `source: "harness"` from the last ledger line, the last transcript phrase and the round. Pids, tokens and exit stay in `openlanes-state.json`.
  - Unacked mail is never read here for a decision. Assignments do not change on it.
- **Done when:** `spec/openlanes/engine/dispatcher_mail_spec.rb` drives a `MemoryStore` message through the thread and finds it once in `state.json`; `spec/openlanes/engine/dispatcher_last_known_state_spec.rb` kills an agent that published nothing and finds the harness entry, and kills one that did publish and finds its agent entry intact.

## B5. Units fold into `plan.md`, `implementation-plan.md` becomes `contract.md`, prompts ask for ack and resume

- **Discipline:** back end (prompts are text the harness ships, not interface; the coupled-rename risk in the spec says one unit)
- **Owns:** `agents/luthen-rael-planner.md`, `agents/luke-backend.md`, `agents/rey-frontend.md`, `agents/hansolo-reviewer.md`, `lib/openlanes/execution/prompt.rb`, `lib/openlanes/execution/executor.rb` (the contract reference only), `lib/openlanes/presentation/documentation.rb`, `lib/openlanes/agents/routing.rb`, `lib/openlanes/plans/status.rb`, `lib/openlanes/linear/unit.rb`, `docs/WORKFLOW.md`, and the specs that name the old files: `spec/openlanes/agents/routing_spec.rb`, `spec/openlanes/agents/registry_spec.rb`, `spec/openlanes/execution/prompt_spec.rb`, `spec/openlanes/plans/ledger_spec.rb`, `spec/openlanes/engine/stay_spec.rb`, `spec/openlanes/engine/runner_spec.rb`, `spec/openlanes/cli/run_spec.rb`, `spec/openlanes/live/live_context.rb`, `spec/openlanes/linear/mapping_spec.rb` if it needs it
- **Must not touch:** `lib/openlanes/engine/dispatcher.rb` and `spec/openlanes/engine/dispatcher_spec.rb` (B4 owns them; if a dispatcher reference to `plan-backend.md` must change, hand it to B4 through `contract.md`), `lib/openlanes/web*`, `lib/openlanes/plans/mailbox.rb`, `lib/openlanes/plans/plan_state.rb`
- **Depends on:** B1 (the ack command it tells agents to run), B2 (the `state resume` command it tells agents to run on INTERRUPT)
- **Shape:**
  - `luthen-rael-planner` writes `## Backend` and `## Frontend` inside `plan.md`; it also states whether the plan has an HTTP surface.
  - `Routing` starts `rey-frontend` only when `plan.md`'s `## Frontend` section holds a unit heading, replacing the `plan-frontend.md` test. Existing folders that still hold `plan-frontend.md` keep working: the old file is read when present (open question 7 assumption: no migration).
  - `luke-backend` writes `contract.md`, plus `openapi.yaml` linked from it when `plan.md` says HTTP. All nine `implementation-plan.md` references renamed.
  - Prompts: `mail ack` right after reading; on INTERRUPT, `openlanes state resume ...` instead of a `RESUME:` mail.
  - D8 option (c), signing already on `state sign`. Unit checkboxes in `plan.md` stay hand edits; record that as the known gap in `contract.md`.
- **Done when:** `spec/openlanes/execution/prompt_spec.rb` asserts the ack and resume instructions appear; `spec/openlanes/agents/routing_spec.rb` covers the `## Frontend` test and the legacy file; `spec/openlanes/presentation/documentation_spec.rb` asserts `openlanes docs` output names neither `plan-backend.md` nor `implementation-plan.md`; `rg implementation-plan lib agents docs` is empty except `lib/openlanes/web.rb` (F1's) and dated decision records; the `linear/mapping.rb` spec passes.

## B6. Optional `openapi.yaml` and `openlanes api docs`

- **Discipline:** back end
- **Owns:** `lib/openlanes/presentation/api_docs.rb` (new: collects `.plans/*/openapi.yaml`, reports a file that does not parse or lacks `openapi:` / `paths:`), `lib/openlanes/cli/api/api.rb` and `lib/openlanes/cli/api/subcommands/docs.rb` (new), the `api` registration in `lib/openlanes/cli.rb`, `spec/openlanes/presentation/api_docs_spec.rb` (new), `spec/openlanes/cli/api_spec.rb` (new)
- **Must not touch:** `agents/*.md` (B5 owns the instruction to write the file), everything under `lib/openlanes/plans`, `engine`, `live`
- **Depends on:** B1 and B2 (all three edit `lib/openlanes/cli.rb`: sequential)
- **Shape:** `ApiDocs#call(tree)` returns found files and problems; the CLI prints a list (and a Redoc link per file) to STDOUT, problems to STDERR, exit non-zero when any file is bad. No real validator.
- **Done when:** `spec/openlanes/presentation/api_docs_spec.rb` builds a `:tree` fixture with two valid files and one missing `paths:`, and gets both plus one problem.
