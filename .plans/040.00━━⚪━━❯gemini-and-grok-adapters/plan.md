# Plan: Choosing the Coding Agent, and the Grok and Gemini Adapters

Five pull requests, in order. Each lands on `main` before the next starts. Q1 to Q6 in `spec.md` were settled with the user; the decisions below follow from them.

## PR 1: a project default adapter

### Decisions

- **D1. `.openlanes.yml` `adapter:`** names the adapter every agent runs on unless its frontmatter or the plan names another. Validated against `Adapters.names`, like `phases.<phase>.adapter`.
- **D2. Precedence** (Q1), highest first: spec.md `phases.<phase>.adapter`, the agent's frontmatter `adapter:`, `.openlanes.yml` `adapter:`, `claude`.
- **D3. An unset frontmatter adapter survives loading.** `Agents::Registry` stops filling in `claude`; `Agent#adapter` is nil when the file names none, and `Profile.resolve` falls back through D2. Every reader of `agent.adapter` (`live/commands.rb` `model!`, the roster) asks the resolved profile instead.
- **D4. "Switching adapters drops the agent's own model"** compares the plan's adapter with the agent's resolved one, so a project default of `codex` does not keep a Claude model name.

### Work units

- [x] `Config` key `adapter:`: member, parser, `to_yaml`, YARD.
- [x] `Registry`/`Agent`: nil when unset; `Profile.resolve` takes the project default.
- [x] Callers of `agent.adapter` move to the resolved profile.
- [x] Docs: `docs/USAGE.md` (`.openlanes.yml`), `openlanes docs` if it lists config keys, architecture.
- [x] Lint, the full suite, and every changed file above 95% coverage.

## PR 2: availability probes

### Decisions

- **D5. Each adapter probes itself.** `Base#probe` returns an `Adapters::Availability` value: `name`, `available`, `reason` (nil when available), `models` (the CLI's list where it has one, else the adapter's priced list), `checked_at`. Probes are local commands run with a timeout and no prompt:
  - claude: `claude auth status --json`, `.loggedIn`.
  - codex: `codex login status`, exit 0; models from `codex debug models --bundled`.
  - pi: `pi --list-models`; at least one model.
  - Not installed (not on `PATH`) is a reason of its own.
- **D6. One result per machine, in Redis** (Q5). Built per machine rather than per project, as `Live::Keys#apps` is: which CLIs are installed and signed in is a fact about the machine, and two machines sharing one Redis would otherwise overwrite each other's answer. `Live::Keys#adapters(machine)` holds the JSON of every adapter's availability, set with an expiry of 20 minutes. Readers only read it.
- **D7. A probe thread in every process that boots** (`engine`, `web`, `run`). Every 15 minutes (Q3), and at boot, it takes `Live::Keys#adapters_lock` with `SET NX EX 60`; the winner probes every adapter and writes D6. A loser does nothing. With Redis unreachable (its outage mode), the process probes for itself and keeps the result in memory.
- **D8. `openlanes agents`** adds an Adapters table: name, available or the reason, capabilities (compacts, resumes, enforces tool denial), model count.
- **D9. The snapshot carries `adapters`** (D5 per adapter, models as `Model#wire`) in place of the claude-only `models`, so the page can draw every adapter's models (Q6).

### Work units

- [x] `Adapters::Availability`, `Base#probe` and the three probes, with a `Runner` seam so specs never start a CLI.
- [x] `Adapters::Probes`: the thread, the Redis lock and key, the in-memory fallback; a row in `docs/thread-safety.md`.
- [x] Booted from `engine`, `web` and `run`, never blocking startup.
- [x] `openlanes agents` Adapters table.
- [x] Snapshot `adapters`; `web/src/api/types.ts`; the demo board.
- [x] Docs, lint, the full suite, coverage.

## PR 3: choosing the adapter in the control room

### Decisions

- **D10. Per-phase selects** (Q6). The new-plan dialog lists the phases its `starts` will walk, each with an adapter select and a model select; "agent's default" writes nothing.
- **D11. An unusable adapter is shown disabled with its reason** (Q2), in the dialog and in every model dropdown. Its models are not offered.
- **D12. The choice lands in spec.md `phases`.** `create_plans` accepts `phases: { <phase> => { adapter, model } }`, validated with `Plans::Spec`'s own rules before `Brief#stamp!` writes it.
- **D13. `ModelSelect` lists the models of the adapter the car actually runs on**, from D9, not claude's.

### Work units

- [x] `IdeaDialog` per-phase rows; `frontmatter.ts`; component tests.
- [x] `Live::Commands#create_plans` and `idea_frontmatter` accept `phases`.
- [x] `ModelSelect` per adapter; `model!`/`switch_model` validated against that adapter.
- [x] Cypress: create a plan with a phase on codex; a disabled adapter shows its reason.
- [x] Docs, lint, the suites, coverage.

## PR 4: grok

### Decisions

- **D14. argv:** `grok -p <prompt> --output-format streaming-json --cwd <root> -s <uuid> --always-approve`, plus `-m`, `--reasoning-effort`, `--deny "Bash(<cmd>*)"` per forbidden command, `--disallowed-tools`, and `--disable-web-search` unless the agent has `network: true`. `-r <id>` resumes.
- **D15. Capabilities:** resumes, enforces tool denial. Compacts only if a recorded headless run shows `/compact` works; otherwise false.
- **D16. Its own transcript dialect:** `text`, `tool_call` (`toolName`, `rawInput`), `usage`, `end` (`sessionId`, totals), `error`, read by a `Stream` subclass or by widening `Stream`'s shapes, whichever leaves `Stream` simpler.
- **D17. Probe:** `grok models`; the first line says signed in or not (its exit code does not), and the rest lists the models.
- **D15, recorded 2026-10-28:** `grok -p "/compact" -r <id>` compacts headless and prints `auto_compact_completed`, so grok compacts. `--deny "Bash(git status*)"` turned the call into a failed tool result, so it enforces tool denial.
- **D18. Confinement is its own capability:** refusing named commands is not holding an agent to its files. `Capabilities#confines` (claude only) now gates confined agents, which grok, codex and pi refuse rather than run unconfined.
- **D19. The session id comes from the argv:** grok names its session only in `end`, which an agent stopped for compaction never prints. The transcript reads the `-s`/`-r` id its command was started with (`Base#transcript(argv:)`).
- **D20. `--disallowed-tools`:** `ask_user_question`, `enter_plan_mode`, `exit_plan_mode` (wait on a person), `scheduler_create` (outlives the run), `send_feedback` (sends to xAI beyond the conversation).

### Work units

- [x] `Adapters::Grok`, registered; argv, effort map, capabilities.
- [x] Transcript dialect, with a recorded fixture under `spec/fixtures/streams/`.
- [x] Probe and models.
- [x] `adapter: grok` runs a phase end to end against the fixture.
- [x] Docs, lint, the full suite, coverage.

## PR 5: gemini

### Decisions

- **D18. argv:** `gemini -p <prompt> -o stream-json --skip-trust --approval-mode yolo --session-id <uuid>`, plus `-m`, `-r <id>` to resume. No effort flag: effort is ignored, and the prompt does not claim otherwise.
- **D19. Tool denial by policy file.** Each invocation writes a TOML policy beside its trace (`decision = "deny"` for each forbidden command prefix, and for `google_web_search` and `web_fetch` unless `network: true`) and passes `--policy`. Capabilities: resumes, enforces tool denial, does not compact.
- **D20. Its own transcript dialect:** `init` (`session_id`), `message` (assistant deltas), `tool_use`, `tool_result`, `error`, `result` (`stats`).
- **D21. Probe reads stderr** (Q4): exit 41 is not signed in; an `IneligibleTierError` is "account tier refused". Built against fixtures from its source; a live run waits for an eligible account.

### Work units

- [ ] `Adapters::Gemini`, registered; argv, policy file, capabilities.
- [ ] Transcript dialect and fixture.
- [ ] Probe with the refused-tier reason.
- [x] Docs, lint, the full suite, coverage.
