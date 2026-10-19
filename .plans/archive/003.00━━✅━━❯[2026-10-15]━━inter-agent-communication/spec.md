# Inter Agent Communication

## What we are trying to achieve

Replace `mailbox.md` with a structured, machine-readable channel between the agents building one plan, carried over Redis and recorded as JSON committed beside the plan. Along the way, give the harness a place to record what an interrupted agent had done, so a restart resumes instead of guessing.

## Why it matters

`luke-backend` and `rey-frontend` build one plan in one worktree at the same time as two separate `claude -p` processes. Today their only channel is `mailbox.md`: append-only Markdown, parsed by a regex (`lib/agentilda/mailbox.rb:29`), polled only when an agent remembers to. Three things follow from that:

- Nothing knows whether a message was read. An agent that stopped reading its mail looks exactly like an agent with no mail.
- Delivery latency is whatever the agent's own judgement of "each significant step" turns out to be (`lib/agentilda/executor.rb:586`).
- A resume note after Ctrl-C is free text (`RESUME: ...`), so the next round has to read and believe prose rather than act on a record.

## What already exists

| Piece                     | Where                                            | Shape today                                                                                              |
| :------------------------ | :----------------------------------------------- | :------------------------------------------------------------------------------------------------------- |
| Mailbox                   | `lib/agentilda/mailbox.rb` (141 lines)           | Markdown, append-only, `flock` + append, numbered headings                                               |
| `mail send` / `mail read` | `lib/agentilda/cli/mail/subcommands/` (86 lines) | the only writer/reader an agent uses                                                                     |
| Run state                 | `lib/agentilda/state_file.rb`                    | `.plans/tmp/agentilda-state.json`, gitignored, one writer, whole-file write + `File.rename` every second |
| Control file              | `lib/agentilda/control.rb`                       | one file per invocation, polled by the agent; `WRAP_UP`, `STOP`, `INTERRUPT`, `WARN:`                    |
| Per-agent wrapper         | `lib/agentilda/dispatcher.rb:312`                | `Thread.new` per running agent, streaming `child.each_chunk` live, with a `Clock` on a timer             |
| Invocation                | `lib/agentilda/executor.rb:358`                  | where `claude -p`'s argv is composed                                                                     |
| Ledger                    | `lib/agentilda/ledger.rb`                        | dated NOTE lines an agent writes into the file named by its `ledger:` frontmatter                        |

## Constraints that shaped every decision below

These are properties of the runtime, not preferences. Each one killed an option that looked reasonable first.

1. **An agent cannot catch a signal or spawn a thread.** `luke-backend` is a `claude -p` process running a model's turn loop. It acts only between tool calls, one at a time, and a long `Bash` or a `Task` wave is minutes during which nothing is checked. This is why `control.rb` exists and why `Control::GRACE` (60s) backs it: the prompt asks, the harness guarantees.
1. **Nothing can put text into a running turn from outside.** The two crossings inward are the control file (agent polls, cadence is the agent's) and a Claude Code hook (runtime injects, cadence is one per tool call). There is no third.
1. **`File.rename` defeats `flock`.** The lock lives on the inode. `StateFile#save` writes a temp file and renames it over the target, giving the file a new inode, so a concurrent writer's lock protects a file that is now unlinked and its write is lost. This is why the run's state file and a multi-writer mailbox cannot be one file.
1. **Redis pub/sub is lossy.** `PUBLISH` to a channel with no subscriber discards the message silently — no error, no queue.

## Decisions

### D1. The state file moves up, out of `tmp/`

`.plans/tmp/agentilda-state.json` → `.plans/agentilda-state.json`. It stays gitignored and machine-local. `StateFile::DIRNAME` goes away; `StateFile::IGNORE` becomes a file line rather than a directory line, and `.for` loses a segment.

Existing checkouts have `.plans/tmp/` in `.gitignore` and a live file in it. Decide at implementation time between migrating on load and leaving the stale directory; do not silently orphan a running harness's state.

### D2. Messages stay in `state.json`

Messages stay in each plan's `state.json` under `messages`. No `mailbox.json` is written. The mailbox gains a `read` field, a `mail ack` command that sets it, and `mail render`, which prints the Markdown view to STDOUT and writes no file.

Decided 2026-10-13 by kig: the mailbox stays in `state.json`; no `mailbox.json` is written.

### D3. `read` is written by the reader, not by delivery

A Redis consumer-group ack says the bytes arrived. It does not say anyone read them. `read: "yes"` is set by an explicit `agentilda mail ack`, which each agent's prompt tells it to issue immediately on reading.

Surface the unacked count on the dashboard. An agent that stopped acking is an agent that stopped reading its mail, which is currently invisible.

An unacked message never affects a round's decisions. The dashboard shows the count and a warning; nothing is held, re-assigned or escalated.

Decided 2026-10-13 by kig: an unacked message is a dashboard count and warning only, never an input to the round.

### D4. Redis is not required for mail

Redis is not required for mail. A run without it still delivers mail.

Decided 2026-10-13 by kig: Redis is not required for mail.

Local Redis with no auth by default. The address comes from `--redis-url`, the configuration file's `redis_url:`, then `$REDIS_URL` as agent-lock reads it, then `redis://localhost:6379/0`; every key is namespaced by the repository and by this machine's node id, a 96-bit digest of `username@hostname`, and machines sharing one Redis never work the same plan (W16 and W26 in `docs/decisions/decisions-on-web-ui-and-review-labels.md`, 2026-10-12).

**Streams (`XADD` / `XREADGROUP`), not pub/sub.** Same effort, and it gives three things pub/sub cannot: a message survives the reader being down, a stream replays what an agent missed, and consumer groups ack delivery.

TTL: Streams have no per-message TTL. The equivalent of the 60-minute window is `XTRIM <key> MINID <now - 60min>` on each write plus `EXPIRE` on the stream key. Nothing is lost by trimming, because the committed JSON is the durable record and Redis is only the transport.

**Key naming must include the checkout, not just the plan ordinal.** Ten sessions run at once here, and two worktrees of this repo both running `001.00` would otherwise cross-talk into each other's streams.

The checkout is identified by its absolute path, resolved through symlinks (`File.realpath`), hashed to keep keys short. It sits below the repository and the node (W26): `agentilda:<repo>:<node>:<checkout>:<plan>:<stream>`, where `<checkout>` is the first 12 hex digits of the path's SHA-256. The path itself is stored beside the keys, in the hash `agentilda:<repo>:<node>:meta` with the username and hostname, so `redis-cli` and the web page can show which machine and checkout a key belongs to. Every worktree has its own path, so two worktrees on one machine never share keys. The remote URL plus the worktree name was considered and rejected for this level: two plain clones of one repository, with no worktree name, would collide. Moving a checkout changes its keys, which costs nothing, because the engine flushes the run to disk (W6) and reloads it from there (decided by the author, 2026-10-12, in `docs/decisions/decisions-on-web-ui-and-review-labels.md`).

### D5. No broker process. The harness thread is the single writer

An earlier draft had one lightweight Ruby process per running plan as the sole writer of the JSON. Dropped: `dispatcher.rb:312` already gives each agent its own thread inside the harness process, already streams the child's output live, and already runs a `Clock` on a timer beside it. That thread drains Redis every second and writes the plan JSON directly, single-writer under a `Mutex`, exactly as `StateFile` does.

This removes the broker's whole lifecycle — spawn, reap, kill on Ctrl-C, orphan cleanup when the harness dies, and "who restarts the broker". Redis keeps the one job only it can do: carrying messages *out* of `claude -p` processes, which are the only actors genuinely outside our process.

Cuts this phase from roughly 4–5 days to 2–3.

### D6. PostToolUse hook is a follow-on, not in this plan

The PostToolUse hook is not in this plan. It is recorded as a follow-on, and its design is kept below for that follow-on.

Decided 2026-10-13 by kig: the PostToolUse hook is not in this plan.

`Executor#argv` (`executor.rb:358`) gains `--settings` with a **PostToolUse** hook running `agentilda mail poll --plan N --for <agent>`. It fires after every tool call the agent makes and returns waiting messages and any `INTERRUPT` as context the model sees immediately.

What it changes: polling stops being a request in the prompt that the agent may forget, and becomes something the runtime does whether or not the agent cooperates. Latency drops from "next time the agent remembers" to "next tool call".

What it does not change: an agent four minutes into one `Bash` call is still unreachable for four minutes. `GRACE` remains the backstop.

Risks: a hook that errors or prints too much disrupts every tool call the agent makes. It must fail silent and cap its output. It was the one item that could be cut without invalidating the rest.

### D7. `last-known-state`, with two writers and a precedence

A `last-known-state` section in the plan's JSON, keyed by agent name, last entry wins, with `round` inside it — an agent interrupted in rounds 1 and 3 should not accumulate entries nobody prunes.

Flow on Ctrl-C: keypress → control file → agent polls (or the hook fires) → agent publishes its state to Redis → harness thread writes it into the JSON. Cooperative and polled, per constraint 1.

Three cases leave the agent writing nothing: terminated when `GRACE` expires mid-tool-call, never reaching another polling point, or dying outright — which is not hypothetical, the state file in the previous worktree shows `"exit": "harness died"` on all four stages. So **the harness is a fallback writer**, from what it already observes: last ledger line, last transcript phrase, round, tokens, exit reason.

The agent's own entry always wins when present. Each entry says which wrote it:

```json
"last-known-state": {
  "luke-backend": {
    "source": "agent",
    "at": "2026-09-17T13:37:04-07:00",
    "round": 1,
    "status": "Interrupted",
    "done": ["Ledger#parse extracted", "specs green"],
    "remaining": ["wire Dispatcher#read_ledger"],
    "next_step": "run bundle exec rspec spec/agentilda/ledger_spec.rb",
    "files_touched": ["lib/agentilda/ledger.rb"]
  },
  "rey-frontend": {
    "source": "harness",
    "at": "2026-09-17T13:37:04-07:00",
    "round": 1,
    "status": "Interrupted",
    "note": "harness died; last seen writing plan-frontend.md"
  }
}
```

A **fixed schema, not freeform**. Freeform JSON is prose with braces, and the next round could not act on it any better than it acts on `RESUME:` today.

**Split:** the semantic resume note goes in the committed plan JSON; pids, tokens and exit codes stay in `.plans/agentilda-state.json`, which is machine-local. Otherwise every interrupted run churns a committed file with process detail nobody reviews.

### D8. `plan-backend.md` / `plan-frontend.md` fold into `plan.md`

`luthen-rael-planner` writes `## Backend` and `## Frontend` sections inside `plan.md` instead of two sibling files. Touches `status.rb` invariants, `linear/units.rb`, `documentation.rb`, and three agent prompts.

**Open problem, must be solved as part of this:** those files are also ledgers. `agents/luke-backend.md:11` declares `ledger: [plan-backend.md, pull-requests.md]`, luke signs `Started` and `Completed` into its own plan file, and `dispatcher.rb:467` appends the harness's `Interrupted` line there too. Merge them and two concurrently running agents do read-modify-write on one file through Claude's `Edit` tool, with no lock. Last writer wins, silently.

Note the race already exists — both agents list `pull-requests.md` as a ledger today. Merging doubles it rather than inventing it.

Options:

- **(a)** Accept it. Both sign into `plan.md`. Simplest; matches the existing tolerance of `pull-requests.md`.
- **(b)** Units merge into `plan.md`, signing moves to a per-agent ledger file. No race, one more file per agent.
- **(c)** *Recommended.* Units merge into `plan.md`, and signing goes through `agentilda ledger sign`, a CLI call that takes `flock` and appends. Agents stop hand-editing ledgers entirely. `Ledger.append` already exists, so this is small, and it fixes `pull-requests.md` at the same time.

### D9. `implementation-plan.md` → `contract.md`

The name is wrong in the same direction as everything else called "plan". `plan-backend.md` says *what luke will build*; `implementation-plan.md` says *what luke built and how to call it* — the interfaces, their shapes, their errors, which files each half owns, which units may run concurrently, and the one integration test proving the halves are joined. `lib/agentilda/documentation.rb:326` calls it "the one file no state requires". Every comment in the repo already calls it the contract.

Nine references: `executor.rb:602`, `documentation.rb:323,326`, `agents/luke-backend.md`, `agents/rey-frontend.md`, `agents/hansolo-reviewer.md`.

### D10. OpenAPI is an optional companion, never the contract

When a plan exposes HTTP endpoints, `luke-backend` also writes `openapi.yaml` beside `contract.md`, and `contract.md` links to it. `luthen-rael-planner` decides in `plan.md` whether the plan has an HTTP surface. A later `agentilda api docs` collects every `.plans/*/openapi.yaml` for Redoc.

OpenAPI is not the contract itself, for three reasons:

- **Most splits are not HTTP.** `luke-backend` is "data, domain, and the API an interface will call" — often a Ruby service object, a GraphQL schema, a TypeScript module, or a CLI. This gem, the thing dogfooded on, has no HTTP surface at all.
- **Half the contract has no OpenAPI slot.** File ownership, unit concurrency, and the integration proof are the half that stops the two agents colliding, and OpenAPI cannot express any of it.
- **It is a harder write target.** A malformed `$ref` breaks the file for rey silently.

Validation starts cheap — parses as YAML, has `openapi:` and `paths:` keys. A real validator gets added only if agents actually produce broken files.

## Phases and effort

| Phase | Content                                                                     | Files | Effort    | Risk                                                |
| :---- | :-------------------------------------------------------------------------- | :---- | :-------- | :-------------------------------------------------- |
| A     | D1 — elevate the state file                                                 | 4     | ~1 day    | low                                                 |
| B     | D2, D3, D8, D9 — JSON mailbox, ack, plan merge, rename                      | ~15   | ~3 days   | medium; the risk is the agent prompts, not the code |
| C     | D4, D5, D7 — Redis Streams, harness as writer, `last-known-state`           | ~8    | ~2–3 days | medium                                              |
| D     | D10 — optional OpenAPI and `api docs`                                       | ~5    | ~1 day    | low                                                 |

A ships alone. B ships alone. C depends on B's JSON format. D is independent of all of them.

## Problem framing

Two framings fit; one is picked.

1. **Transport framing.** The problem is that mail rides on append-only Markdown, so move it onto Redis Streams and make Redis the channel. Rejected: research shows messages already live in each plan's `state.json` (`lib/openlanes/plans/plan_state.rb:188-200`), and kig decided Redis is not required for mail (D4).
1. **Observability framing.** The problem is that nobody can tell whether a message was read, and that an interrupted agent leaves prose rather than a record. Transport is secondary; the missing pieces are a read receipt, a structured resume record, and the file/ledger tidy-ups that make two agents stop colliding.

**Picked: observability.** Most of the transport is already built (research, "Already built"), so what is left is the read receipt (D3), the resume record (D7), the `plan.md` / `contract.md` consolidation (D8, D9), and Redis as an optional faster path (D4, D5).

### Tightening from the research

The decision table above predates the `openlanes` rename and part of the build. Where a decision text and the table below disagree, the table wins:

| Decision | Delta that remains | Anchor |
| :-- | :-- | :-- |
| D1 | None to build. State file already at `.plans/openlanes-state.json` with a legacy fallback; the stale `.plans/tmp/` is left alone | `lib/openlanes/engine/state_file.rb:18,25,60` |
| D2 | `read` field, `mail ack`, `mail render` (STDOUT). Messages stay in `state.json`; no `mailbox.json` | `lib/openlanes/plans/mailbox.rb:20,65` |
| D3 | All of it | `lib/openlanes/cli/mail/subcommands/` holds `send.rb`, `read.rb` only |
| D4, D5 | Optional Redis path for mail, on the existing `Live::Store` seam | `lib/openlanes/live/store.rb:142-198` |
| D6 | Not in this plan | decided 2026-10-13 |
| D7 | All of it | none exists |
| D8 | Units only: merge `plan-backend.md` / `plan-frontend.md` into `plan.md`. Signing already goes through the locked `state sign` | `lib/openlanes/execution/prompt.rb:171-176`, `agents/luthen-rael-planner.md:13,35-36` |
| D9 | All of it | `lib/openlanes/presentation/documentation.rb:323,326` |
| D10 | All of it | none exists |

## Goal

After this ships, the two agents building one plan can see whether the other has read their mail, an interrupted agent leaves a fixed-schema resume record the next round acts on instead of a free-text `RESUME:` note, and the plan's folder holds one `plan.md` (with Backend and Frontend sections) and one `contract.md` rather than four files with "plan" in the name.

## Non-Goals

- **Not replacing the Markdown ledger.** `Ledger` NOTE entries stay human-readable in documents (D8).
- **Not committing `openlanes-state.json`.** It describes one machine's run.
- **Not push delivery into a running turn.** Constraint 2 says it cannot be built; D6 is deferred.
- **Not a PostToolUse hook.** Decided out of this plan, 2026-10-13.
- **Not a `mailbox.json`.** Messages stay in `state.json`.
- **Not a broker daemon.** Dropped in D5.
- **Not making Redis mandatory for mail**, and not changing the degraded path in `Engine::Runner#claim` (`lib/openlanes/engine/runner.rb:135-141`).
- **Not acting on unacked mail.** A count and a warning on the dashboard, never an input to a round (D3).
- **Not OpenAPI for non-HTTP interfaces**, and not a real OpenAPI validator in the first cut (D10).
- **Not converting an in-flight `mailbox.md`.** It stays beside the JSON as history (`mailbox.rb:86`).

## In scope

Each item has its check.

1. **Read receipt.** A message in `state.json` carries `read` (`"no"` default, `"yes"` after ack). Check: spec asserts `mail send` produces `read: "no"` and `mail ack <n>` flips it, leaving other messages untouched.
1. **`mail ack`.** A new subcommand under `lib/openlanes/cli/mail/subcommands/`, writing through `PlanState`'s locked path. Check: spec under a `:tree` fixture; two concurrent acks both land.
1. **`mail render`.** Prints the plan's whole exchange as Markdown to STDOUT and writes no file. Check: spec asserts STDOUT content and that the plan folder is unchanged.
1. **Unacked count on the dashboard.** The board shows the count and a warning when it is non-zero. Check: spec on `Engine::Board` / the web view; a spec asserting a round's assignments are identical with and without unacked mail.
1. **Agent prompts tell agents to ack.** `luke-backend`, `rey-frontend` and the shared prompt instruct `mail ack` right after reading. Check: the prompt spec asserts the instruction appears.
1. **Optional Redis delivery for mail.** When Redis is reachable, mail is also carried on a stream through `Live::Store`; when it is not, `mail send` still writes `state.json`. Check: a shared example run against `Live::Store` and `Live::MemoryStore` (`spec/openlanes/live/store_examples.rb`), and a spec with `Live::Unavailable` that still delivers.
1. **Harness thread as the writer of Redis-borne messages.** The per-agent thread in `Dispatcher` writes drained messages into `state.json` under the plan lock. Check: spec drives a `MemoryStore` message through the thread and finds it in `state.json`.
1. **`last-known-state`.** A fixed-schema section in `state.json` keyed by agent, last entry wins, with `source: agent | harness`; an agent entry is never overwritten by a harness one. Check: schema file under `schemas/plan-state.schema.json` validates both shapes; spec for precedence; spec that machine detail (pid, tokens, exit) is absent from the committed file.
1. **Harness fallback writer.** On interrupt or death with no agent entry, the harness writes `source: harness` from the last ledger line, transcript phrase, round. Check: spec kills an agent without a published state and finds the harness entry.
1. **Units merged into `plan.md`.** `luthen-rael-planner` writes `## Backend` and `## Frontend` in `plan.md`; `status.rb` invariants, `linear/units.rb`, `documentation.rb`, and the three agent prompts follow. Check: `openlanes docs` regenerates with no mention of `plan-backend.md`; the `linear/mapping.rb` spec still passes.
1. **`implementation-plan.md` → `contract.md`.** All nine references renamed. Check: `rg implementation-plan` over `lib agents docs` returns nothing, and the suite is green.
1. **Optional `openapi.yaml`.** `luke-backend` writes it when `plan.md` says the plan has an HTTP surface; `contract.md` links to it; `openlanes api docs` collects `.plans/*/openapi.yaml`. Check: spec that a fixture with two files yields both, and that a file with no `openapi:` / `paths:` keys is reported.
1. **Suite and lint stay green.** `bundle exec rspec` 0 failures, `just lint` zero offenses, coverage not below the baseline of 98.63%.

## Out of scope

| Item | Reason |
| :-- | :-- |
| PostToolUse hook (D6) | Decided out, 2026-10-13. Whether `--settings` hooks load under `--restricted` is untested (`lib/openlanes/adapters/claude.rb:87-92`); design stays in D6 for a follow-on |
| `mailbox.json` | Decided 2026-10-13; messages stay in `state.json` |
| Acting on unacked mail | Decided 2026-10-13; would stall rounds on model compliance, not on a fault |
| Deleting `.plans/tmp/` or its `.gitignore` line | Irreversible and gains nothing; the load fallback already reads it |
| Real OpenAPI validation | Add only if agents produce broken files |
| Making Redis mandatory | Decided 2026-10-13; it would remove a working channel |
| Committing the machine-local state file | It describes one machine's run |

## Back end / front end

`luke-backend` and `rey-frontend` build these as a pair; the contract goes in `contract.md` once D9 lands, and in `implementation-plan.md` until then.

| Item | Back end (`luke-backend`) | Front end (`rey-frontend`) |
| :-- | :-- | :-- |
| Read receipt, `mail ack` | `Plans::Mailbox`, `PlanState`, CLI subcommand | none |
| `mail render` | `Mailbox` Markdown view, CLI subcommand | none |
| Unacked count | expose the count from `Plans::Mailbox` | show count and warning on the board and web page (`Engine::Board`, `lib/openlanes/web.rb`) |
| Redis path, harness writer | `Live` seam, `Dispatcher` thread | none |
| `last-known-state` | `PlanState`, schema, `Dispatcher` fallback | render the section on the web page, if the page lists per-agent state |
| Units into `plan.md`, rename to `contract.md` | `status.rb`, `documentation.rb`, `linear/units.rb` | agent prompts and the web page's file list (`lib/openlanes/web.rb:25`) |
| `openapi.yaml`, `api docs` | CLI command, collector | none (Redoc rendering is a link, not a build) |

## Open questions

Answered by kig on 2026-10-13 and recorded in the decisions above: where messages live (D2), what an unacked message means (D3), whether Redis is required (D4), the hook (D6). Everything below is an assumption or an unsettled item.

1. **D8 option.** Assumed (c): units merge into `plan.md`, signing stays on the locked `state sign`. Research says signing is already locked, so what remains is hand edits to `plan.md` checkboxes, which take no lock. Confirm (c), or accept (a).
1. **Key layout.** D4 gives `agentilda:<repo>:<node>:<checkout>:<plan>:<stream>`; the code and W26 use `openlanes:<repo>:<node>:<checkout>:<stream>` with no plan segment (`lib/openlanes/live/keys.rb:14-40`). Assumed: follow the code, carry the plan in the message. Confirm.
1. **What "Redis is not required" means for the first cut.** Assumed: Redis is a faster, optional path alongside the always-written `state.json`. If it should be dropped from this plan entirely, phase C shrinks to D7.
1. **Does a harness thread drain Redis each second?** Not traced by research (`Dispatcher`, `Live::Subscriber`). Unverified.
1. **Do luke and rey edit the same plan file concurrently today?** Needs a run log, not a read; it decides whether (a) is actually safe.
1. **`mail ack` argument.** Assumed: a message number, as `mailbox.rb` numbers messages. A form acking everything for an agent is not specified.
1. **Existing plan folders.** Assumed: plans with `plan-backend.md` / `implementation-plan.md` keep them; only new plans use the new names. Whether `resync dirs` should migrate old ones is unspecified.
1. **Schema versioning.** Adding `read` and `last-known-state` changes `plan-state.schema.json`; assumed a field addition, no `version` bump. Confirm.
1. **Naming.** The spec text says `agentilda`; the tool is `openlanes`. Assumed `openlanes` throughout.

## Risks to planning or execution

- **Prompt risk, not code risk.** Phases B and C change what three agent prompts ask for; a prompt that agents ignore leaves `read: "no"` forever and the dashboard permanently warns. Mitigate by making the warning informational and by asserting the prompt text in specs.
- **Coupled rename.** D8 and D9 touch `status.rb`, `documentation.rb`, `linear/units.rb`, `linear/mapping.rb` and agent prompts together; a partial change fails the invariants or the mapping spec. Ship them in one unit.
- **Schema churn.** `schemas/plan-state.schema.json` gains fields while old folders exist; a strict validator must tolerate their absence.
- **Concurrent writes to `state.json`.** The harness thread and `mail ack` both write; both must go through the `openlanes-plan-<key>.lock` path (`plan_state.rb:252-257`) or acks are lost silently.
- **Self-hosting.** The plan changes the files that the harness running it relies on; run it with a pinned checkout of the tool.
- **Spec staleness.** The decision text uses old names and paths; a planner reading D4 literally would build the wrong key layout. The tightening table above is the corrective.
- **Effort.** Original estimate 7–9 days across phases A–D; phase A is already built, so roughly 6–8.

## Conclusion

When this ships, a message in a plan's `state.json` records whether it was read, `mail ack` sets that and `mail render` prints the exchange to STDOUT, and the dashboard counts what was never acked without ever changing a round. Redis Streams carry mail faster when available and are never required. An interrupted agent leaves a fixed-schema `last-known-state` entry that the harness completes when the agent could not. Plan folders hold `plan.md` with Backend and Frontend sections and `contract.md`, and an HTTP plan may carry an `openapi.yaml` that `openlanes api docs` gathers.

## Research

Sources are the repository at `openlanes.worktrees/003.00-inter-agent-communication` (branch `kig/003.00-inter-agent-communication`, clean), read on 2026-10-13. No web sources were needed: every question was answered by code or the repo's own decision log. The spec's paths (`lib/agentilda/...`, `.plans/tmp/agentilda-state.json`, `mailbox.md`) are from the earlier codebase. The tool is now `openlanes`, and several decisions below are already built.

Test baseline: `RBENV_VERSION=4.0.6 bundle exec rspec` → `2214 examples, 0 failures`, coverage 98.63% (`/tmp/leah-rspec.log`).

### Already built: the spec is partly stale

| Decision | State in repo | Anchor |
| :-- | :-- | :-- |
| D1 state file moved up | Built. Path is `.plans/openlanes-state.json`; `load` falls back to `.plans/tmp/openlanes-state.json` when the new path is empty; nothing writes or deletes the legacy file | `lib/openlanes/engine/state_file.rb:18,25,60`, `.gitignore` lists both paths |
| D2 mailbox as JSON, committed | Partly. Messages are in each plan's `state.json` under `messages`, not a `mailbox.json`. `mailbox.md` is still read as history. `mail render` does not exist | `lib/openlanes/plans/mailbox.rb:20,65`, `lib/openlanes/plans/plan_state.rb:188-200` |
| D3 `read` set by `ack` | Not built. No `read` field, no `mail ack` | `lib/openlanes/cli/mail/subcommands/` has `send.rb` and `read.rb` only |
| D4 Redis Streams | Not for mail. Redis is used for the live board, claims and commands, through `redis-client` with Streams and consumer groups | `openlanes.gemspec:78`, `lib/openlanes/live/store.rb:142-198` |
| D6 PostToolUse hook | Not built. Nothing passes `--settings` or a hook to `claude` | `lib/openlanes/execution/executor.rb`, `lib/openlanes/adapters/claude.rb` |
| D7 `last-known-state` | Not built | none |
| D8 fold into `plan.md` | Not built. `luthen-rael-planner` still writes `plan-backend.md` and `plan-frontend.md`; `luke-backend` and `rey-frontend` still list them as ledgers | `agents/luthen-rael-planner.md:13,35-36`, `agents/luke-backend.md:11`, `agents/rey-frontend.md:9` |
| D8 signing race | Signing already goes through a locked command into `state.json`; the prompt forbids hand edits | `lib/openlanes/execution/prompt.rb:171-176`, `lib/openlanes/plans/plan_state.rb:163,252-257` |
| D9 `implementation-plan.md` → `contract.md` | Not built. The name `implementation-plan.md` is used in code, prompts and docs; `contract.md` is named only as the contract spec | `lib/openlanes/presentation/documentation.rb:323,326`, `agents/luke-backend.md:26`, `lib/openlanes/web.rb:25` |
| D10 OpenAPI | Not built | none |

Constraint 3 (`File.rename` defeats `flock`) is already handled: the lock is a sibling file in `Dir.tmpdir`, `openlanes-plan-<key>.lock`, not the data file (`plan_state.rb:252-257`).

### Answers to the seven questions

1. **D1: migrate or leave the stale directory?** Leave it. The `load` fallback already reads it, and nothing deletes it. The `.plans/tmp/` line in `.gitignore` can stay until no checkout holds a legacy file. Deleting it would be irreversible under R2 and gains nothing.
2. **D8: option (c)?** Largely built for signatures, since `state sign` is already the locked path. What remains is the unit checkboxes in `plan-backend.md` and `plan-frontend.md`. Merging units into `plan.md` needs the three agent prompts, `status.rb` invariants, `documentation.rb` and `linear/` to change together. Recommendation: (c), with the merge limited to units. Writes that go through `PlanState` already take `openlanes-plan-<key>.lock`; hand edits to `plan.md` take no lock, so they are the gap.
3. **D3: what does an unacked message mean?** Nothing today: there is no ack. Recommendation: a dashboard count only. A round decision that waits on an agent acknowledging mail would stall on model compliance, not on a fault. This is a product call; I recommend the dashboard and flag it as open.
4. **D6: first cut or follow-on?** Follow-on. Nothing else depends on it. One constraint is unverified: `claude.rb:87-92` passes `--restricted`, which the code comment says stops settings files from granting more. Whether `--settings` hooks still load under `--restricted` must be tested before anyone designs around it.
5. **Old `mailbox.md` in flight?** Converted: no. It is read as history by `Mailbox#legacy` (`mailbox.rb:86`), and new numbering continues from its highest number (`mailbox.rb` `append`, `after: legacy...max`). Leave it beside the JSON.
6. **`mail render`: file or STDOUT?** STDOUT. The house rule is already followed: `mail read` prints the messages with `puts` (`cli/mail/subcommands/read.rb`). A `mail render` would print the whole plan's exchange, and never write a file.
7. **Redis client and seam?** Use `redis-client`, already a dependency. The seam exists: `Live::Store` is the wrapper, `Live::MemoryStore` is the in-process fake, and `spec/openlanes/live/store_examples.rb` holds both to the same contract (`store.rb:48`, `memory_store.rb:1-20`).

### Contradictions

- **Redis is a hard dependency (D4) vs degraded (runner).** D4 says a missing Redis is a clear error. `Engine::Runner#claim` runs unclaimed when Redis is unreachable (`lib/openlanes/engine/runner.rb:135-141`), and `Live.connect` raises `Live::Unavailable` (`lib/openlanes/live.rb:53`). Production runs the degraded path. Mail does not touch Redis today, so making it require Redis would remove a working channel. Settle this before D4 is built.
- **Key layout (D4) vs W26.** D4 gives `agentilda:<repo>:<node>:<checkout>:<plan>:<stream>`. The code and `docs/decisions/decisions-on-web-ui-and-review-labels.md` (W26) use `openlanes:<repo>:<node>:<checkout>:<stream>`, with no plan segment (`lib/openlanes/live/keys.rb:14-40`). `<repo>` is the normalised GitHub URL, not a path. Node id (24 hex, `node.rb:46`) and checkout id (12 hex of `File.realpath`, `node.rb:56-62`) match D4.
- **D1 "StateFile::IGNORE becomes a file line".** Already true (`state_file.rb:31`), but D1 also says `.for` loses a segment (`state_file.rb:` `self.for`).
- **Plan folder file names.** The spec uses `mailbox.json`; the repo stores messages in `state.json`. Pick one.


### Could not settle

1. Whether `claude --settings <hook file>` still fires PostToolUse under `--restricted` (D6). Needs a live run with a stub hook.
2. Whether luke and rey edit `plan-backend.md` checkboxes concurrently with each other today. Needs a run log, not a read.
3. Whether a harness thread drains Redis every second (D5). Not checked; `Dispatcher` and `Live::Subscriber` were not traced end to end.
4. Whether D3's unacked count should ever affect a round. A product decision (see answer 3).
5. Whether D4 requires Redis for mail, or only for the board (see contradictions).

### Conclusion

The chapter's answers reduce the spec to four live decisions: D2 (mail already in `state.json`; close the `mailbox.json` naming), D4 (the Redis-required contradiction, and the key layout), D6 (cuttable, untested under `--restricted`), and D8 (units-only merge plus the `plan-*.md` prompt changes). D1, D7 and D9 need only their remaining deltas. D10 is independent.
