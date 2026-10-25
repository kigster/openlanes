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

- **Q1, precedence:** agent frontmatter beats `.openlanes.yml`. An agent names an adapter only when it depends on it (chewie-verifier needs Claude's browser tools); the project default fills in everywhere else.
- **Probes are per adapter.** Each adapter class defines its own `probe`, so a new adapter brings its own. A probe is local and fast; an unavailable adapter carries the reason (not installed, not signed in, no models).
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

## What research needs to settle

- gemini's headless flags, stream format, tool denial, resume and auth probe.
- Whether `grok models` reaches the network; if it does, whether the probe is still acceptable at startup.
- grok's `streaming-json` event shapes, for `Adapters::Stream` and the spinner phrase.
- What exit code `codex login status` returns when signed out.
- How a stale probe is refreshed: a login after startup should not need a restart.
- What the UI shows for an adapter that is installed but not signed in (hidden, or disabled with the reason).

## How to tell it's working?

- `adapter: grok` and `adapter: gemini` run a phase end to end against recorded transcripts. No spec reaches the network.
- `openlanes agents` reports each adapter's capabilities and availability, with the reason when unavailable.
- `adapter: codex` in `.openlanes.yml` runs every agent without its own `adapter:` on codex; chewie-verifier stays on claude.
- The new-plan dialog offers only available adapters, and the choice lands in `spec.md` `phases`.
- Startup time does not grow: the probes run on their own thread.
