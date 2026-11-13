# Contract 069.00: `/restart-web`, `/status`, `/stats`

Owner: backend-coder. No HTTP route is added or changed, so there is no `openapi.yaml`.

## Baseline

The suite was green on `main` per `CLAUDE.md` (0 failures). After this plan: `bundle exec rspec` gives 6686 examples, 0 failures, 9 pending (environment skips because `web/dist` is not built in this worktree); details in `pull-requests.md`.

## Interfaces the page uses

All travel over the existing copilot message route (`CopilotMessage {id, text}`) and the copilot event stream. The page parses nothing.

### `/restart-web`

- Input: the text `/restart-web`, no arguments. `/restart-web 3` is answered at once with the usage and "/restart-web takes no arguments." as turn `<id>.1`.
- Queued as engine command `{kind: "restart_web", plan: null, agent: null, payload: {source: "copilot"}}`. Refused by the server with `Unanswered` ("no engine is running to apply /restart-web") when no engine runs, as `/stop` is.
- Engine reply, turn `<id>.1`:
  - `done: restarting the control room: supervisor <pid> stops it, rebuilds the page and starts it again; the page reconnects when it is back`
  - `refused: `/restart-web` needs `openlanes start`; no supervisor is running.` when no supervisor runs, its PID file is stale, or it was started with `--no-web`.
- After the server comes back, one more copilot turn, id `web-restart-<epoch>`, from `copilot`, kind `text`:
  - `The control room restarted on a rebuilt page. The page was rebuilt.`
  - `The control room restarted on its old page. <Reason>.` where reason is one of: the build failed (exit N), so the old page stays[: build output tail]; the page was not rebuilt: npm is not on PATH; the page was not rebuilt: <dir>/package.json is missing; the build ran past 300 seconds and was stopped, so the old page stays.

### `/status`, `/status NNN`, `/stats`

- Never queued; answered at once as turn `<id>.1` from `copilot`, engine or not. `/stats x` and `/status 1 2` get the usage plus why.
- Read from the engine snapshot in Redis (`keys.snapshot`). With none: `No engine is running on this node, so there are no figures yet.`
- `/status`: `N plan(s) on the board:` then one line per plan: `NNN.MM <emoji> <label> · <title> · <agents> · $<cost>`; `No plan is on the board.` when empty.
- `/status NNN`: that plan's line, then `  <agent>: <state>, round <n>, <model>[, <s>s left][ · <message>]` per agent; `NNN.MM is not on the board.` when absent.
- `/stats`: `Run <status>[, since <iso>]`, `agents working: a of j`, `plans on the board: n`, `tokens: <up> in, <down> out`, `cost: $x.xx`.
- amended: `/stats` reads the run totals the snapshot already carries rather than a new Tally key in Redis, as plan.md settled. The snapshot is published every tick with up, down, cost, agents and jobs; a second key would write the same facts twice.

## File ownership

- backend-coder: everything under `lib/`, `spec/`, `agents/copilot.md`, `README.md`, `spec/fixtures/golden/container_wiring/agents_list.txt`.
- frontend-coder: `web/src/copilot/*`, `web/cypress/lanes/restart-web.cy.ts`, `bin/lanes-e2e`.
- Shared: none.

## Build order

B1 slash grammar → B2 supervisor restart and B3 engine handler → B4 boot note, B5 queries → B6 docs. F1 needs B1's names; F2 needs B3 and B4.

## Integration proof

`web/cypress/lanes/restart-web.cy.ts` under `bin/lanes-e2e`: a real `openlanes start`, nothing stubbed; type `/restart-web`, see the `restarting the control room` reply, the page reconnect, the boot note turn (`/build|rebuil/i`), and `/stats` answered.
