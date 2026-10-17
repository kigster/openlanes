# Plan 020.00: Lanes with No Active Agents

Three slash commands typed into the copilot (`/stop NNN`, `/restart NNN`, `/concurrency N`) become engine
commands on the existing command stream (W13). They never reach c3po-operator: the copilot agent stays read-only, and
the only write path is the gate the page's buttons already use, so idempotency, replies and logging come for free.

## Shape of the change

- `POST /api/copilot` recognises a message starting with `/`. A known slash command becomes a `Live::Command` whose
  id is the message id, queued on `commands`; the person's turn is stored as today. No `claude -p` runs.
- Three new command kinds: `stop_plan` (plan), `restart_plan` (plan), `set_concurrency` (payload `limit`). The
  existing `stop` stays per-agent; new names avoid overloading it.
- `Live::Commands` applies them to the dispatcher. A command with `payload.source == "copilot"` also gets its reply
  written to the copilot stream as turn `"<id>.1"`, so the page's existing wait (`answers(turn, id)`) ends when the
  engine answers, and the conversation keeps the outcome.
- An unknown or malformed `/word` is answered at once with a copilot text turn listing the three commands. A slash
  command sent while no engine is live is refused with 503.
- Lowering concurrency never kills an agent: `Dispatcher` fills only while `@running.size < @runner.jobs`, so a lower
  limit takes effect as agents finish (the spec allows the wait).

## Order and dependency graph

```
B1 ─┬─> B2 ─> B3 ─> B5 ─┐
    └─> B4 ─────────────┼─> F1 ─> F2 ─> I1
```

- B1 first: B3 and B4 both parse the new kinds.
- B2 and B4 run in parallel after B1. B3 needs B2. B5 needs B3 (reads the limit B3 records).
- F1 needs B4 (wire shape) and B5 (`run.jobs`). F2 needs F1.
- I1 last.
- No file is owned by two units. F1 and F2 are sequential anyway (F2 consumes F1's types).

## Backend

### B1 Command kinds

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/command.rb`, `spec/openlanes/live/command_spec.rb`
- **Must not touch:** `commands.rb`, `copilot.rb`, `web/`
- **Depends on:** nothing
- **Done when:** `spec/openlanes/live/command_spec.rb` shows `stop_plan` and `restart_plan` need a plan and no agent,
  and `set_concurrency` needs payload `limit` and no plan.

Add the three to `KINDS`; `stop_plan` and `restart_plan` to `PLAN_KINDS`; `"set_concurrency" => %w[limit]` to `PAYLOAD`.

### B2 Dispatcher and Runner controls

- **Discipline:** back end
- **Owns:** `lib/openlanes/engine/dispatcher.rb`, `lib/openlanes/engine/runner.rb`,
  `spec/openlanes/engine/dispatcher_lane_controls_spec.rb` (new), `spec/openlanes/engine/runner_spec.rb`
- **Must not touch:** `lib/openlanes/live/*`
- **Depends on:** B1
- **Done when:** `dispatcher_lane_controls_spec.rb` and `runner_spec.rb` pass.

Signatures:

- `Runner#jobs=(n)`: Integer ≥ 1; raises `OpenLanes::Error` under `--isolation shared` (jobs pinned to 1) and for n < 1.
- `Dispatcher#stop_plan(ordinal) → Array<String>` (keys told STOP): `Execution::Control::STOP` to every running job on
  the plan, then `runner.drop_plan(ordinal)` so it is not assigned again, and the plan's claim released when the run
  has claims. Raises `OpenLanes::Error` when the plan is neither running nor in scope.
- `Dispatcher#restart_plan(ordinal) → void`: raises when any job on the plan is running ("it already has an agent") or
  the plan is not on this node's board (in scope or claimed). Otherwise `runner.add_plan`, clear the dropped mark and
  the exhausted-rounds history that keeps it from dispatch, `wake!`. This is the "Redis glitch left a lane with no
  agent" repair.
- `Dispatcher#concurrency=(n)`: delegates to `Runner#jobs=`; never signals a running agent.

Spec cases: stop on a pair signals both agents; restart refused while running; restart of an idle in-scope plan
dispatches on the next tick; lowering 3 → 1 with three running keeps all three and starts nothing until two finish.

### B3 Command handlers and copilot echo

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/commands.rb`, `lib/openlanes/live/run_state.rb`,
  `spec/openlanes/live/lane_commands_spec.rb` (new), `spec/openlanes/live/run_state_spec.rb`
- **Must not touch:** `command.rb`, `copilot.rb`, `lib/openlanes/engine/*`
- **Depends on:** B1, B2
- **Done when:** `spec/openlanes/live/lane_commands_spec.rb` passes against `MemoryStore`.

- `HANDLERS` gains `stop_plan`, `restart_plan`, `set_concurrency`, each returning a reason string ("stopped 2 agents on
  020.00 and took it off the board", "020.00 restarts at the next tick", "concurrency 4 → 3; the run waits for one
  agent to finish") or raising `Refusal`.
- `set_concurrency`: `limit` must be an Integer ≥ 1. Recorded in `RunState` (`#concurrency`, `#set_concurrency`) so a
  restarted engine and the snapshot read it.
- `reply`: for `payload["source"] == "copilot"`, the same `MULTI` also `xadd`s a copilot `Turn` (`"#{id}.1"`,
  `from: "copilot"`, `kind: "text"`, status and reason) to `@keys.copilot`. `answer_again` writes no turn, so a
  redelivery never duplicates it.

### B4 Slash parser and the copilot route

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/copilot/slash.rb` (new), `lib/openlanes/live/copilot.rb`, `lib/openlanes/web/app.rb`,
  `agents/c3po-operator.md`, `spec/openlanes/live/copilot/slash_spec.rb` (new), `spec/openlanes/live/copilot_spec.rb`,
  `spec/openlanes/web/app_spec.rb`
- **Must not touch:** `commands.rb`, `command.rb`, `lib/openlanes/engine/*`
- **Depends on:** B1
- **Done when:** `slash_spec.rb`, `copilot_spec.rb` and the new examples in `app_spec.rb` pass.

- `Live::Copilot::Slash.parse(text, id:) → Live::Command | Slash::Help | nil`: nil when text does not start with `/`;
  `Help` (usage text) for an unknown or malformed slash (`/stop` without a plan, `/concurrency x`); otherwise a
  `Command` with `payload.source = "copilot"`. Plans go through `Plans::Ordinal.parse`, so `/stop 20` and
  `/stop 020.00` both work.
- `Copilot#say` stores the person's turn, then: a `Command` is `xadd`ed to `@keys.commands`; a `Help` is answered at
  once with turn `"<id>.1"`. Neither calls the responder, so `Unanswered` is raised only for plain text.
- `POST /api/copilot`: `answer_later` skipped for slash messages. When no engine node has a live heartbeat
  (`@keys.nodes`), a slash command is refused 503 "no engine is running to apply /stop".
- `agents/c3po-operator.md`: one paragraph saying these commands exist and that it may suggest them, never run them.

### B5 Concurrency on the board

- **Discipline:** back end
- **Owns:** `lib/openlanes/live/snapshot.rb`, `spec/openlanes/live/snapshot_spec.rb`, `lib/openlanes/web/demo_board.rb`,
  `spec/openlanes/web/demo_board_spec.rb`
- **Must not touch:** `commands.rb`, `dispatcher.rb`, `web/`
- **Depends on:** B3
- **Done when:** `snapshot_spec.rb` shows `run.jobs` is the current limit after `set_concurrency`.

`Snapshot#run` gains `jobs: Integer`, so the page and the integration check see `/concurrency` take effect.

## Frontend

### F1 Wire types and run header

- **Discipline:** front end
- **Owns:** `web/src/api/types.ts`, `web/src/api/fixtures/*.json` (the `run` object only), the run-header component
  under `web/src/shell/` that shows `agents_working`, and its `*.test.tsx`
- **Must not touch:** `web/src/copilot/*`, `lib/`
- **Depends on:** B4, B5
- **Done when:** the header's test shows "3 of 4 agents" from `run.agents_working` and `run.jobs`.

The three kinds join the `Command` kind union; `jobs: number` joins the run type.

### F2 Slash hint in the copilot composer

- **Discipline:** front end
- **Owns:** `web/src/copilot/Copilot.tsx`, `web/src/copilot/copilot.css`, `web/src/copilot/Copilot.test.tsx`
- **Must not touch:** `web/src/api/*`, `lib/`
- **Depends on:** F1
- **Done when:** `Copilot.test.tsx` shows a hint listing `/stop`, `/restart`, `/concurrency` while the box starts with
  `/` and not otherwise, and that the engine's `"<id>.1"` turn ends the "reading" state.

No client-side parsing: the server owns the grammar (B4), so page and server cannot disagree. The hint is display
only. A person's turn starting with `/` is drawn monospace, as a command.

### I1 Integration check

- **Discipline:** front end
- **Owns:** `web/cypress/lanes/lanes.cy.ts` (new), `web/cypress.lanes.config.ts` (new), `web/cypress/lanes/fixtures/`
  (three plan specs), `bin/lanes-e2e` (new), `justfile` (`lanes-e2e` recipe)
- **Must not touch:** `web/cypress/e2e/*`, `web/cypress/factory/*`, `lib/`
- **Depends on:** B1–B5, F1, F2
- **Done when:** `OPENLANES_LANES_E2E=1 just lanes-e2e` passes.

Modelled on `bin/factory-e2e`: real agents spend real tokens, so it is gated by `OPENLANES_LANES_E2E=1` and never part
of the everyday suite. `bin/lanes-e2e` builds a temp git project with three quick-lane plans (each writes one small
text file), starts `openlanes start -j 3 --isolation worktree`, and runs Cypress against its control room. Nothing is
stubbed. Through the page only, it must show:

1. Three cars running; the header reads `3 of 3`.
2. `/concurrency 2` → the copilot answers done; the header limit reads 2; no car is killed.
3. `/stop <plan A>` → done; A's cars leave the board within a tick.
4. `/restart <plan A>` → done; a car for A reappears. `/restart <plan B>` while B runs → refused, "already has an agent".
5. `/frobnicate` → a help turn listing the three commands.

## HTTP surface

Yes, changed; no new route. `POST /api/copilot` behaves differently for messages starting with `/` (and may answer 503
for a slash command with no live engine); `Command` gains three kinds; `GET /api/board`'s `run` gains `jobs`.
`luke-backend` updates `contract.md` and writes `openapi.yaml` beside it covering those three endpoints.
