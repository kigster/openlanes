# Decisions on agent speed, lanes, adapters, plan state and evals

Date: 2026-10-06. Made without a grilling session (the author was away and asked for decisions to be taken and reviewed afterwards).

Review, 2026-10-06: the author kept all ten decisions, D1 to D10, unchanged.

## Why runs were slow: measured, not guessed

From the seven traces of plan `025.00` (`$TMPDIR/openlanes-traces/20261006-*`):

| Agent | Model | Effort | Wall | API time | Turns | Cost |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| leah-researcher | haiku | xhigh | 56s | 41s | 14 | $0.17 |
| yoda-writer | sonnet | xhigh | 456s | 429s | 39 | $1.80 |
| palpatine-planner | opus | xhigh | 231s | 208s | 20 | $1.56 |
| luke-backend (round 1) | fable | xhigh | 137s | 1998s | 7 | $21.70 |
| rey-frontend (round 1) | fable | xhigh | 702s | 632s | 21 | $5.40 |
| luke-backend (round 2) | fable | xhigh | 703s | 1188s | 48 | $12.76 |
| rey-frontend (round 2) | fable | xhigh | 192s | 612s | 20 | $6.93 |

1. Every agent loaded the operator's whole personal setup: 46 plugins, 60 MCP servers, 358 skills, 455 slash commands, 27 sub-agent types and 17 hook events per start. A one-word prompt costs ~43.5k context tokens and 4.7s in that configuration, against ~33.4k and 2.1s with `--setting-sources project,local --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands`. Agents re-read that context on every turn.
2. `xhigh` effort on every agent, and Fable on both builders.
3. luke-backend fanned out through the `Agent`/`Task` tool: 98 sub-agent tool calls in one round, 1998s of API time inside 137s of wall clock, $21.70.
4. rey-frontend ran on a plan whose front end was a few lines of terminal output.
5. Every plan walked the full spine (leah, yoda, palpatine) even when the author already knew what to build.

## Decisions

### D1. Agents run lean by default

The Claude adapter passes `--setting-sources project,local`, `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` and `--disable-slash-commands`. The project's own `CLAUDE.md` and settings still load. `openlanes run --user-config` restores the old behaviour for a run that needs a personal plugin. `--bare` was rejected: it reads only `ANTHROPIC_API_KEY`, and the executor deliberately scrubs that so subscription auth is used.

### D2. Models and effort, capped at Opus

| Agent | Before | After | Why |
| --- | --- | --- | --- |
| leah-researcher | haiku / xhigh | haiku / medium | lookup work |
| yoda-writer | sonnet / xhigh | sonnet / medium | prose, not reasoning |
| palpatine-planner | opus / xhigh | opus / high | the one place depth pays |
| luke-backend | fable / xhigh | opus / high | cap at Opus |
| rey-frontend | fable / xhigh | sonnet / medium | UI work is narrower, and only runs when there is some |
| hansolo-reviewer | opus / high | sonnet / high | asked for: Sonnet reviews |
| lando-broker | sonnet | haiku / low | folding answers is clerical |
| r2d2-mechanic (new) | — | haiku / medium | short mechanical tasks |

`Adapters::Claude::CEILING` clamps anything above Opus (Fable, or a full `claude-fable-*` id) to Opus, wherever the model came from: agent frontmatter, spec override or `run --model`. Builders lose the `Task` tool, so they stop fanning out sub-agents.

### D3. The front end only starts when there is front end to build

`rey-frontend` declares `needs: [plan-frontend.md]` and `toggle: frontend`. It is dispatched only when `plan-frontend.md` holds at least one work-unit heading, and never when `spec.md` says `frontend: false`. `frontend: true` forces it. Palpatine is told to write `plan-frontend.md` only when there is interface work.

### D4. Lanes, chosen in `spec.md` frontmatter

```yaml
---
lane: quick        # full (default) | plan | quick
frontend: false    # optional; true forces, false forbids, absent = decided by plan-frontend.md
depth: fast        # fast | medium | deep, optional, sets the default effort
phases:            # optional per-phase overrides
  build: { adapter: codex, model: gpt-5-codex, effort: medium }
  review: { model: opus }
---
```

- `full`: leah → yoda → palpatine → luke (+ rey) → han. Today's behaviour.
- `plan`: skips research and rewriting. The harness writes a blank `plan.md` and moves the folder ⚪️ → 📋 itself (an existing edge), and palpatine plans from the spec as written.
- `quick`: skips research, rewriting and planning. The harness writes a one-unit `plan.md` (`## Task`) and moves the folder ⚪️ → ⭐️ through the existing `plan` event, where `r2d2-mechanic` is the only builder serving the lane. It takes the plan 🟡 → 🟢, and Han still reviews. No new state and no new edge were needed.
- `openlanes create --lane quick "split large migration"` writes the frontmatter.

Agents declare the lanes they serve (`lanes: [full]`, …). Absent means every lane.

### D5. Per-agent coding agent, model and effort, overridable per phase

Agent frontmatter gains `adapter:` (claude, codex or pi; claude by default) and `phase:` (research, specification, planning, build, frontend, review, unblock). `effort:` is validated against `low medium high xhigh max`. A spec's `phases:` map overrides `adapter`, `model` and `effort` for the agent whose `phase` matches. Precedence, highest first: `run --model` → spec `phases.<phase>` → spec `depth` (effort only) → agent frontmatter.

### D6. Adapters

`OpenLanes::Adapters` holds `Base` (the interface), plus `Claude`, `Codex` and `Pi`. An adapter turns an `Invocation` (prompt, root, model, effort, tool grants, network) into an argv and a transcript parser. Each one translates effort into its own vocabulary (`--effort`, `-c model_reasoning_effort=…`, `--thinking`). The autonomy boundary's post-check (HEAD unmoved, no new remote ref) is CLI-independent, so it still holds for every adapter. Codex runs with `--sandbox workspace-write`, which has no network by default. Pi has no sandbox, so the post-check is its only guard, and the docs say so.

### D7. `state.json` in every plan folder

Every plan folder gets a committed `state.json`, validated against `schemas/plan-state.schema.json`. It holds:

- the plan's identity, lane and last known state
- every stage: agent, phase, round, adapter, model, effort, status, timestamps, tokens, cost, exit, note, next
- the message log between agents
- the stage running now, with pid and run id, so a crashed harness can be resumed

Writes are atomic: a lock file, a temp file, then a rename. Agents never edit it by hand. They call `openlanes state sign` and `openlanes mail send`, which write through the lock. The dispatcher reads signatures from `state.json` first and falls back to the markdown ledger, so existing plans keep working. Messages now land in `state.json`, and `mailbox.md` is still read for older plans. Folder names stay the source of truth for state; `state.json` records the last state the harness moved the folder to, and `resync dirs` updates it.

### D8. Evals per agent, at the requested depth

`evals/cases/<agent>/<case>.yml` describes a fixture plan (and repository files), the depth asked for, and the checks. `openlanes eval` (and `just eval`) scores each case. Every agent is checked twice:

- **did it finish the task:** the state reached, files present or absent, required sections, the ledger signed, the paths it changed and the paths it left alone
- **did it work at the depth requested:** words and pattern counts (sources, units, findings) between per-depth bounds, plus `max_seconds` and `max_tokens`. Too shallow fails at `deep`; too slow or too large fails at `fast`.

Each case ships two recordings: `pass/` must pass and `fail/` must fail. Each is laid out as `plan/`, `repo/` and `run.json`, and a spec enforces both, so the scorers are themselves tested. Offline scoring is the default and runs in CI. `--live` runs the real agent in a temp git repo, under a token cap (300,000 by default). All 8 agents are covered by 11 cases; leah, palpatine and r2d2 each have cases at two depths. Coding and review agents are not checked for their final state, because reaching it needs a published PR and a review verdict, which an eval never produces. Their checks cover the signature, the diff and the paths left untouched.

### D9. Delivery

Two stacked pull requests: the module reorganisation (pure move plus facades, #40), then everything in this document on top of it. Commits are atomic per decision.

### D10. SOLID, applied where it pays

- **Single responsibility.** `Execution::Prompt` now owns what an agent is told, and `Executor` owns running it: 741 lines became 485 + 313. `Agents::Profile` decides adapter, model and effort. `Agents::Routing` decides who gets a plan. `Lifecycle::Lanes` decides which phases a plan skips. Each was previously inline in the executor or the dispatcher.
- **Open/closed.** A new coding agent is a new `Adapters::Base` subclass plus one registry entry. Nothing in the run loop changes.
- **Liskov.** Every adapter's transcript answers the same interface as `Execution::Transcript`, so the executor and the board cannot tell them apart.
- **Interface segregation.** The CLI depends on each namespace's facade (`Plans.tree`, `Agents.registry`, …) rather than on its classes.
- **Dependency inversion.** The executor depends on the adapter interface, not on `claude`. `spawn:` and the `GitHub` and `Linear::API` seams stay injectable.
- **Not done.** `Engine::Dispatcher` (~770 lines) still mixes dispatch, settlement and crash recovery. Settlement shares six pieces of dispatcher state, so extracting it is a refactor of its own and was left out to keep this pull request reviewable.
