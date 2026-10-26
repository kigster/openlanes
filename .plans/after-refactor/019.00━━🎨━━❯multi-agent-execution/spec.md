---
created: 2026-10-16
starts: research
---

# Multi Agent Execution

# Multi-Agent Execution

If any of the agents performing a specific task are able to parallelize execution, and are able to fan out sub-agents, it would be ideal if the tile showing the agent indicates that multiple agents are working on it in parallel. 

## Visual Changes

To do that, proposal  is to close the box that shows an agent with two, or three or more vertical lines indicating multiplicity. If it's possible to know exactly the number of subagents, it should be reflected in the number of lines. If it's not possible, then just showing 2 additional vertical lines on the right side of the rectangle depicting an agent is sufficient. Once the sub-agents terminate, it should go back to a single

## How to test 

Verify in the browser that an agent that faned out is visually different then the rest

<!-- cmd:01M52V2M09MXFP6DPFFGZREYS6 -->

## What we are trying to achieve

An agent tile on the web board that shows, at a glance, how many sub-agents that agent has running now, and returns to a plain tile when they finish.

## Why it matters

A fanned-out agent looks identical to a single one, so a person cannot tell why it burns tokens faster or runs longer.

## What already exists

The engine counts sub-agents per row (`Board::Row#subagents`, `engine/board.rb:82`); the web tile never receives the number (see Research, Q1-Q2).


## What research needs to settle

The list is empty, so these questions come from the goal and `How to test`: can the tile show how many sub-agents an agent has, and can it drop back to one line when they end.

## Framing

Two ways to state the problem:

1. **Display problem.** The tile needs a visual marker. Data is assumed available; draw lines.
1. **Data problem.** The tile cannot show "running now" because the engine only counts sub-agents ever started, and the snapshot drops even that (Research Q2, Q3). Fixing the picture without fixing the number produces a tile that gains lines and never loses them.

**Picked: the data problem.** The spec requires the tile to return to one line, and Research Q3 shows no current figure can do that.

## Goal

After this ships, a person looking at the web board can tell which agents are fanned out and by how many: a tile with N sub-agents in flight is drawn with N extra vertical lines, and when they end the tile is single again. Today every tile looks the same whatever the agent is doing underneath.

## Non-Goals

- Showing what a sub-agent is doing. The parent stream does not carry it (Research Q5).
- Cumulative sub-agent counts or per-sub-agent token spend on the tile.
- Making Codex or Pi fan out, or report sub-agents. They report none (`adapters/stream.rb:65`).
- Any change to scheduling, `jobs`, or isolation. This is display of what the agent already does itself.
- The retired ratatui TUI; its doc line is stale (Research, Contradictions).
- Restyling the rest of the tile.

## In scope

Each item has its check.

1. **In-flight count in `Transcript`.** Count of tasks started and not yet terminal, keyed by `task_id`; a `task_notification` whose `status` is `completed`, `failed` or `stopped` ends the task. Check: a `transcript_spec.rb` example feeding start, start, notification(completed) yields 1, then 0 after the second notification.
1. **Count survives a resumed session.** The executor adds earlier spawns on resume (`executor.rb:302`); the in-flight figure must not inherit finished ones from a prior session. Check: an `executor_spec.rb` example where a resumed run begins at 0 in flight.
1. **Board row carries the in-flight number.** `Board::Row#subagents` (`board.rb:82`) is refreshed each tick (`dispatcher.rb:977`) from the in-flight count. Check: `dispatcher_spec.rb` example in which the row falls back to 0 after the notification.
1. **Snapshot exposes it.** `Live::Snapshot#car` (`snapshot.rb:184-204`) gains `subagents:` (integer, 0 when none). Check: `snapshot_spec.rb` asserts the key.
1. **Wire type.** `Car` in `web/src/api/types.ts:36-54` gains `subagents: number`, and `sampleCar` is updated. Check: `tsc` passes and the sample has the field.
1. **Tile draws the lines.** `Car.tsx` adds a class and `min(N, 3)` extra vertical lines on the right edge when `car.subagents > 0` (cap and unknown-count rule: open question 2). `board.css` near `.car` (`:48`) holds the style. Check: a Cypress or component test sets `subagents` 0, 1, 3 and asserts the number of line elements and that 0 draws none.
1. **Accessible text.** The tile exposes a `title`/`aria-label` such as "3 sub-agents running". Check: same test asserts the attribute.

## Out of scope

- Per-sub-agent activity lines: not in the stream (Research Q5).
- Changing `Tally` cumulative accounting (`engine/tally.rb`): spend is a separate figure and still needs the cumulative count.
- Other machines' read-only boards beyond carrying the same field: they render the same `Car` component, so they get it free; no extra work is scoped.
- Terminal UI output of the count: no consumer exists.

## Back end / front end

| Item | Built by |
| :--- | :--- |
| 1 In-flight count in `Transcript` | `backend-coder` |
| 2 Resume handling | `backend-coder` |
| 3 Board row | `backend-coder` |
| 4 Snapshot key | `backend-coder` |
| 5 Wire type and sample | `frontend-coder` (shape agreed with backend-coder: integer, never null) |
| 6 Tile lines and CSS | `frontend-coder` |
| 7 Accessible text | `frontend-coder` |

## Open questions

Nothing below needs a human before planning; each carries the default the planner should use.

1. **Does the pinned `claude` emit `task_notification` with `status`?** (Research, Could not settle 1-3.) Unverified against a live run. Default: build item 1 against the documented shape; first work unit is to record one stream and confirm. If absent, fall back to "count never drops" is **not** acceptable to the spec, so escalate to a human then.
1. **Line mapping.** The spec says N lines when the number is known. Assumed: draw `min(N, 3)` extra lines, and 2 extra lines when the count is unknown. Cap and unknown-case are assumptions; confirm with the owner at review.
1. **Does the lines marker use a CSS pseudo-element or real elements?** Assumed real elements (testable in item 6).
1. **Timed-out or killed sub-agent.** Unknown whether a terminal notification is emitted (Research, Could not settle 2). Default: when the parent invocation ends, the in-flight count is reset to 0.
1. **Wording of "count of sub-agents" in the board** for read-only boards from older engines that omit the field: assumed the UI treats a missing `subagents` as 0.

## Risks to planning or execution

- The only source for terminal status is a third-party SDK doc (Research Q3). If the real stream differs, item 1 changes shape. Mitigation: recording step first.
- `web/src/board/sample.ts` was held by another agent per the comment in `types.ts`; check for a concurrent edit before touching it.
- `Transcript#spawned` is used by cumulative consumers (`tally`, `executor`); reusing it for in-flight would break them. Add a separate field.
- Cypress coverage for the board needs the web stack up; planning should budget for that.

## Conclusion

When this ships, `Transcript` knows how many sub-agents are in flight, the board row and snapshot carry it as `subagents`, and the web tile draws extra vertical lines while the number is above zero and reverts to a plain tile when it returns to zero. Codex and Pi tiles stay plain. The one fact still to be confirmed on a live recording is that `claude` emits a terminal `task_notification`.

## Research

Repo read at this worktree, `git ls-files` clean. Sub-agent figures below are the `claude` stream; Codex and Pi report none (`adapters/stream.rb:65`).

### Questions and answers

1. **Does the engine know the sub-agent count?** Yes, as a running total. Each `task_started` sets `@spawned = @tasks.size` (`execution/transcript.rb:406`), and `task_progress`/`task_notification` update tokens only (`:413-420`). `Board::Row#subagents` carries it (`engine/board.rb:82`), refreshed each tick (`engine/dispatcher.rb:977`).
2. **Does the web tile get it?** No. `Live::Snapshot#car` has no `subagents` key (`live/snapshot.rb:184-204`). The wire `Car` type has none (`web/src/api/types.ts:36-54`). `web/src/board/Car.tsx:22-64` draws name, model, activity and stats only. `web/src` never mentions sub-agents.
3. **Can it go back to one line when sub-agents end?** Not from current data. The count only rises, so it never falls (`transcript.rb:406,418`). `task_notification` is handled as a token update and its `status` is never read (`transcript.rb:386`). Upstream docs say `task_notification` marks the terminal state, with `status` of `completed`, `failed` or `stopped` ([hexdocs TaskNotification, retrieved 2026-10-16](https://claude-code.hexdocs.pm/ClaudeCode.Message.SystemMessage.TaskNotification.html)). That is a third-party SDK, not verified against a live `claude` run. In-flight = started minus terminal, keyed by `task_id`.
4. **Is the count per invocation?** No. A resumed session adds the earlier spawns (`execution/executor.rb:302`), so the figure is per agent, across sessions.
5. **Can sub-agent activity be shown?** No from the parent stream. Sub-agent internal events are not propagated, per an open feature request ([claudeissues #43553, retrieved 2026-10-16](https://claudeissues.com/issue/43553-feat-propagate-sub-agent-internal-events-in-output-format-stream-json)). Only the count is available.

### Contradictions

- Spec says the tile returns to one line when sub-agents end. The counter only rises (`transcript.rb:406,418`).
- `docs/superpowers/specs/2026-09-11-ratatui-tui-dashboard-design.md:60` lists a sub-agent count column. The repo has no ratatui code. Production runs the web board (`web/src/board/`), which has no such column. Treat the ratatui doc as stale.
- Board row has `subagents` (`engine/board.rb:82`), the snapshot drops it. The engine and the screen disagree on what a car carries.

### Could not settle

1. Does the pinned `claude` CLI emit `task_notification` with `status` on stream-json? Settle: one `claude -p --output-format stream-json --verbose` run with a prompt that spawns one sub-agent, then `jq 'select(.subtype=="task_notification")'`.
2. Does a sub-agent killed by timeout still emit a terminal `task_notification`? Settle: same recording, forcing a timeout.
3. How often does `task_progress` arrive during a long sub-agent? Settle: timestamps from the same recording.

### Findings, Conclusion & References

- The data is half there. The engine counts sub-agents, the web tile gets none, and the count never drops.
- Smallest path: (a) add `subagents` to `Snapshot#car` and the `Car` type; (b) track in-flight in `Transcript` from `task_notification.status`; (c) draw the lines in `Car.tsx`, plus `board.css` near `.car` (`:48`).
- Open: item 1 above decides whether (b) is needed. Without it, a count that never drops is the only honest figure.
- Verified: `bundle exec rspec spec/openlanes/execution/transcript_spec.rb spec/openlanes/live/snapshot_spec.rb` gives 55 examples, 0 failures, this worktree, 2026-10-16.
- Sources: [hexdocs ClaudeCode TaskNotification](https://claude-code.hexdocs.pm/ClaudeCode.Message.SystemMessage.TaskNotification.html), third-party SDK, retrieved 2026-10-16. [claudeissues #43553](https://claudeissues.com/issue/43553-feat-propagate-sub-agent-internal-events-in-output-format-stream-json), retrieved 2026-10-16. No paywalled or licensed sources.
