---
created: 2026-10-20
starts: research
depends_on: ["038.00"]
---

# Gemini and Grok Adapters

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 3 of 7. Widened on 2026-10-25 to cover choosing the coding agent, not only adding two more.

## What we are trying to achieve

1. **Two more adapters.** xAI's `grok` CLI first, then Google's `gemini` CLI, built on the capability contract from 038.00. The Executor degrades where a capability is missing; with no deny-list, the Boundary after-check is the only guard.
2. **Providers discovered, not assumed.** The list of usable adapters is built at runtime: each adapter checks that its CLI is on `PATH` and signed in. A background thread runs the probes when `openlanes start`, `web` or `run` boots, never blocking startup, and caches the result.
3. **The coding agent is chosen in three places**, highest precedence first:
   1. the plan: `spec.md` `phases.<phase>.adapter` (exists), now also settable from the new-plan dialog in the control room;
   2. the agent: `adapter:` in `agents/*.md` frontmatter (exists), for agents that depend on one CLI;
   3. the project: a new `adapter:` key in `.openlanes.yml`, the default for every agent that names none;
   4. `claude`, when nothing else says.

## Why it matters

No vendor lock-in: every phase can run on claude, codex, pi, gemini or grok. And a choice the UI offers must be one that can actually run: `pi` installed with no provider signed in is not a usable adapter.

## What already exists

- `Adapters::Base`, `Claude`, `Codex`, `Pi`, `Stream`, `Capabilities`; `Adapters::DEFAULT = "claude"` is hard-coded.
- `Agents::Profile.resolve`: plan override, then agent frontmatter. `Registry` validates `adapter:` names.
- `Plans::Spec` `phases.<phase>` with `adapter`, `model`, `effort`, validated against `Adapters.names`.
- The control room's `IdeaDialog` (starts, research, front end, depth) and `ModelSelect` (static model list per adapter).

## Decisions so far (2026-10-25)

- **Q1, precedence:** agent frontmatter beats `.openlanes.yml`. An agent names an adapter only when it depends on it (verifier needs Claude's browser tools); the project default fills in everywhere else.
- **Probes are per adapter.** Each adapter class defines its own `probe`, so a new adapter brings its own. A probe is local and fast; an unavailable adapter carries the reason (not installed, not signed in, no models).
- **Q2, an unusable adapter in the UI (2026-10-27):** listed but disabled, with the reason ("gemini: account tier refused", "pi: no provider signed in"). Nothing that cannot run can be picked, and the operator sees what to fix.
- **Q3, a stale probe (2026-10-27):** every adapter is re-probed on a timer, every 15 minutes, on the same background thread. A login made while the factory runs shows up within that. Credential-file mtimes were rejected: token refresh rewrites them, and an env-var key leaves no file.
- **Q4, gemini on an account it refuses (2026-10-27):** built anyway, as the last pull request, against fixtures built from its source. Its probe reads stderr and reports the refused tier, so the UI shows it disabled; a live run waits for an eligible account.
- **Q5, where probes run (2026-10-27):** shared through Redis. `start` runs the engine and the web as separate processes, so one result is kept under a project key that every process reads; whichever process finds it due probes, under a short lock so two never probe at once.
- **Q6, the dialog (2026-10-27):** per-phase selects. The new-plan dialog lists the phases the plan will walk, each with an adapter and a model select; a phase left on its agents' default writes nothing.
- **Probe commands found on this machine:**

  | CLI | Probe | Signed in when | Time |
  | :-- | :-- | :-- | --: |
  | `claude` 2.1.310 | `claude auth status --json` | `.loggedIn == true` | 0.18 s |
  | `codex` 0.164.0 | `codex login status` | exit 0 | 0.02 s |
  | `pi` 1.0.4 | `pi --list-models` (`pi auth check --provider X --json --no-refresh` for the reason) | at least one model listed | 0.24 s |
  | `grok` 1.0.46 | `grok models` | "You are logged in", models listed | 0.47 s |
  | `gemini` 0.51.0 | to be researched | | |

- **Models come from the probe where the CLI lists them** (`pi --list-models`, `grok models`), replacing hard-coded lists in `ModelSelect`.
- **grok maps closely to claude:** `-p` / `--prompt-file`, `--output-format streaming-json` (NDJSON), `-m`, `--reasoning-effort`, `--deny` / `--disallowed-tools` / `--disable-web-search` (so it enforces tool denial), `--resume` / `--session-id` (so it can compact), `--sandbox`.

## Research findings (2026-10-27)

Gathered from `--help`, bundled docs and source, and probes run under a throwaway `HOME`. No prompt was sent to any model.

- **gemini 0.51.0, headless:** `-p <text> -o stream-json`, and `--skip-trust` (or `GEMINI_CLI_TRUST_WORKSPACE=true`), without which it exits 55.
  - Events: `init` (`session_id`, `model`), `message` (`role`, `content`, `delta`), `tool_use` (`tool_name`, `tool_id`, `parameters`), `tool_result`, `error`, `result` (`status`, `stats` with `input_tokens`, `output_tokens`, `cached`).
  - `-m` for the model; no effort flag (thinking is a settings key only).
  - No working deny flag: `--policy <file.toml>` with `decision = "deny"` rules (`toolName`, `commandPrefix`) is the way, and `google_web_search` / `web_fetch` are denied the same way.
  - `--approval-mode yolo`; `-r <uuid>` resumes, `--session-id <uuid>` names a new session.
  - Signed out: exit 41, a plain-text message on stderr. Signed in, the check is a network call of about 3.5 s that also refreshes `~/.gemini/oauth_creds.json`.
  - **This machine's account is refused:** free-tier OAuth answers `IneligibleTierError … migrate to the Antigravity suite`, and the exit code (42, "no input") hides it, so a probe must read stderr.
- **grok 1.0.46:** `--output-format streaming-json`, NDJSON with `type` on every line: `text`, `thought`, `tool_call` (`toolName`, `rawInput`), `tool_call_update`, `usage` (per response), `end` (always last: `sessionId`, `usage`, `num_turns`, `total_cost_usd`), `error`.
  - The session id arrives only on `end`, so the adapter passes `-s <uuid>` to know it up front.
  - `--deny "Bash(git push*)"`, `--disallowed-tools`, `--disable-web-search`, `--reasoning-effort`, `--sandbox`, `--always-approve`, `-r <id>`, `--cwd`.
  - `grok models` exits 0 signed in or out; its first line says which ("You are logged in…" / "You are not authenticated."). It reaches the network only when `~/.grok/models_cache.json` is stale (about an hour); 0.4 to 1.2 s.
- **codex:** `codex login status` exits 1 signed out, 0 signed in, 0.05 s. `codex debug models --bundled` lists models offline.
- **pi:** no provider signed in on this machine (`pi --list-models` lists none). `pi auth check --provider X --json --no-refresh` gives the reason.
- **claude:** `claude auth status --json`, 0.13 s; no model-listing command.
- **Credential files** (`~/.codex/auth.json`, `~/.grok/auth.json`, `~/.gemini/oauth_creds.json`, `~/.pi/agent/auth.json`; claude in the keychain) are rewritten on token refresh, and env-var keys leave no file, so watching their mtime cannot say when a probe is stale.

## How to tell it's working?

- `adapter: grok` and `adapter: gemini` run a phase end to end against recorded transcripts. No spec reaches the network.
- `openlanes agents` reports each adapter's capabilities and availability, with the reason when unavailable.
- `adapter: codex` in `.openlanes.yml` runs every agent without its own `adapter:` on codex; verifier stays on claude.
- The new-plan dialog offers only available adapters, and the choice lands in `spec.md` `phases`.
- Startup time does not grow: the probes run on their own thread.
