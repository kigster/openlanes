# Contract: 020.00 Lanes with No Active Agents

Owner: luke-backend. HTTP surface: [`openapi.yaml`](openapi.yaml).

## Baseline

`bundle exec rspec` before any back-end change: 3081 examples, 1 failure, 9 pending.

- `spec/openlanes/live/snapshot_spec.rb:129` ("has the fixture's keys at every level"): the page's fixture already
  carries `run.jobs` (rey's F1, in flight); the snapshot did not. B5 adds it, so this is not a pre-existing defect.

## Interfaces rey calls

### `POST /api/copilot` with a slash message

Request unchanged: `{ "id": "<ulid>", "text": "/stop 20", "plan"?: "..." }`.

| Text                         | Effect                                                                        | Response                       |
| ---------------------------- | ----------------------------------------------------------------------------- | ------------------------------ |
| `/stop <plan>`               | person's turn stored; `Command{kind: "stop_plan", plan}` queued on `commands` | 202, as today                  |
| `/restart <plan>`            | same, `kind: "restart_plan"`                                                  | 202                            |
| `/concurrency <N>`           | same, `kind: "set_concurrency"`, `payload.limit: N` (Integer)                 | 202                            |
| `/anything-else`, `/stop`, `/concurrency x` | person's turn, then a copilot help turn `"<id>.1"` at once     | 202                            |
| any of the three, no engine heartbeat in `nodes` | nothing stored                                        | 503 `{"error": "no engine is running to apply /stop"}` |

`<plan>` is anything `Plans::Ordinal.parse` takes: `20`, `020`, `020.00`. Commands carry `payload.source: "copilot"`.
Plain text (no leading `/`) behaves exactly as today.

### The answer the page waits on

The engine answers each slash command on `replies` as today (`Reply{id, status, reason}`), and also appends a copilot
turn to the copilot stream: id `"<id>.1"`, `from: "copilot"`, `kind: "text"`, `text`: `"<status>: <reason>"`, e.g.
`done: 020.00 restarts at the next tick` or `refused: 020.00 already has an agent: luke-backend`. That turn is what
ends the page's "reading" state. A help turn has the same id and shape, text starting `Slash commands:`.

Reasons, as built:

- `stop_plan`: `stopped N agent(s) on 020.00 and took it off the board`; refused `020.00 is not on this run's board: ...`.
- `restart_plan`: `020.00 restarts at the next tick`; refused `020.00 already has an agent: <names>` or
  `020.00 is not on this node's board`.
- `set_concurrency`: `concurrency 4 → 3; the run waits for 1 agent to finish` (no wait clause when not lowering below
  what runs); refused `concurrency must be a whole number of at least 1, ...` or `this run is --isolation shared: ...`.

### `GET /api/board` (snapshot)

`run.jobs: Integer`: the current concurrency limit, after any `/concurrency`.

### `Command` kinds

`stop_plan` (plan, no agent), `restart_plan` (plan, no agent), `set_concurrency` (no plan, `payload.limit`).

## File ownership

- luke: `lib/**`, `spec/**`, `agents/c3po-operator.md`, `openapi.yaml`, this file.
- rey: `web/**`, `bin/lanes-e2e`, `justfile` (`lanes-e2e` recipe).
- Shared: none. `web/src/api/fixtures/*.json` is rey's; `snapshot_spec.rb` reads it.

## Build order

B1 → B2 → B3 → B5; B1 → B4. F1 needs B4 and B5; F2 needs F1; I1 last.

## Integration proof

`OPENLANES_LANES_E2E=1 just lanes-e2e` (rey's I1): real engine at `-j 3`, Cypress through the copilot, nothing stubbed.
