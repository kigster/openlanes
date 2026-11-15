---
created: 2026-11-10
starts: planning
depends_on: [none]
frontend: true
task-completed-when:
  - "The event stream sends only what changed since the last event, and a page that reconnects gets one full board"
  - "An agent's drawer can ask that agent to hold, to wrap up, and to stop, and shows that it was heard"
  - "A plan's row shows its reviewers' findings and lets a person strike one"
  - "Every plan row and agent drawer shows dollars spent so far"
---
# Make Openlanes More Interactive

## What needs to be done

- More interactive

  - Send board deltas, not full snapshots, over the existing event stream; full boards grow with plans and machines.
  - **Steer a running agent from its drawer.** The control file exists; expose **"send a note", "extend time" and "stop after this step"** (check first: I only confirmed **set_concurrency**).
  - Show the diff and the reviewers' findings in the plan row, with accept or strike buttons that feed the arbitrator.
  - Show the cost and elapsed time per plan and per agent live, using the token meter you already stream.

## What we are trying to achieve

A control room a person can steer the run from, not only watch it in.

## Why it matters

Today the page shows what agents do, but most ways of changing it mid-run mean a terminal.

## What already exists

Checked against `main` on 2026-11-10. More of this exists than the items above assume.

- **Stream.** `Live::Publisher` appends a whole snapshot to a Redis stream on every change and `GET /api/events` relays it; `web/src/api/useBoard.ts` reconciles by each node's `seq`.
- **Steering.** `Live::Commands::HANDLERS` already accepts `message`, `hold`, `wrap_up`, `stop`, `compact`, `set_model`, `switch_model`, `stop_plan`, `restart_plan` and `set_concurrency`, and `Execution::Control` writes the control file. The page sends only `message` (`AgentDrawer.tsx`), the two model commands (`ModelSelect.tsx`) and `stop_all`. So "send a note" exists, and hold, wrap up and stop need buttons, not a back end. Extending an agent's time is asked through the existing question flow (#62).
- **Findings.** A plan on the wire already carries `findings: { struck, critical, headings }` (`web/src/api/types.ts:144`), and the arbitrator's rulings are in `state.json`. The diff is not on the wire.
- **Cost.** Each plan and the run carry `cost` in dollars; an agent's car carries `up`, `down` and `elapsed` but no cost. The page shows only the run's total (`Header.tsx`) and elapsed times.

## Notes for whoever builds this

- Deltas: keep `seq`, send a JSON Patch or changed plans only, and a full snapshot on connect and on any gap in `seq`. The fixtures under `web/src/api/fixtures/` and the demo board (`Web::DemoBoard`) must speak the same protocol.
- A person striking a finding is a new authority: today only the arbitrator strikes. Record who struck it in `state.json`, and treat it as the arbitrator's strike everywhere it is read (`Prompt#review_section`).
- Showing a diff means a new endpoint beside `GET /api/plans/:ordinal/files`; link to the pull request's "Files changed" first and measure whether an inline diff is wanted.
- Plan 062.00 adds the dollar cap; show spend against it once it exists.
- Plan 056.00 adds a top-level nav and 058.00 a settings page to the same app; coordinate the layout.

## Decisions needed

- Whether a person may strike a reviewer's finding from the page, or only accept the arbitrator's ruling.

## How to tell it's working?

- bundle exec rspec spec/openlanes/live spec/openlanes/web
- cd web && npm test && npm run typecheck
- just web-e2e
