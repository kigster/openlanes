---
depends_on: ["010"]
---

# Init Interview

## Problem statement

`lanes init` interviews in the terminal: who merges, build quality, then the stack, with AI extraction from a free-text description, and porting when an existing stack is to be replaced. `--reconfigure` re-runs it.

Merge mode, build quality and stack are project-wide decisions that every later agent depends on (M4, M5, M16, M18 in `docs/decisions/decisions-on-merge-modes-and-verification.md`).

Today `openlanes init` asks four values (project, lane, frontend, jobs) through tty-prompt (`lib/openlanes/cli/init/init.rb:3`, `:67-77`). `Config::KEYS` is `project lane frontend jobs redis_url commands` and `Config.parse` rejects anything else (`lib/openlanes/support/config.rb:84`), so `merge.by`, `build_quality` and `stack` cannot be stored at all.

### Framings considered

1. **Interview-first.** Replace the four prompts with one inquirex flow (M16): merge, quality, stack, with extraction. Everything else follows from the flow.
1. **Config-first.** Add `merge`, `build_quality`, `stack` to `Config` and take them from flags only; the interview comes later.

Picked **config-first inside an interview-shaped delivery**: the keys, `-y` path and detection are built first and stand alone, and the interactive flow is a thin layer over them. Reason: the research found the inquirex gems cannot be installed together as M16 describes (`inquirex-tty` pins `inquirex ~> 0.9.5`, local is 0.10.0), so the data model must not wait on that decision.

## Goal

After this ships, `openlanes init` records three project-wide decisions in `.openlanes.yml` (`merge.by`, `build_quality`, `stack`) and writes `docs/decisions/stack.md`. On a terminal it gets there by asking who merges, how much quality to buy, and what the stack is, detecting what the folder already holds and, with an API key, extracting answers from a free-text description so the questions it answered are skipped. `--reconfigure` re-runs it with the current answers as defaults and shows the diff before saving.

## Non-Goals

- The web copilot version of the questionnaire (M16, v2.0).
- Acting on `merge.by` or `build_quality`: the merge engine, polling, depth and model defaults of M4/M5 are other plans. This plan only stores the values.
- Executing a port: generating the "Port from X to Y" plan, leah's inventory and chewie's parity check (M18) are later work. This plan records `from`/`to` and asks the question.
- Fixing the inquirex gems upstream (M17).
- Installing toolchains or scaffolding application code for the chosen stack.
- Changing `-y` semantics for the existing four values.

## In scope

Each item is checkable by a spec or a command.

1. `Config::KEYS` accepts `merge` (`by: human|agent`), `build_quality` (`top_notch|high|medium|mvp`) and `stack`; `Config.parse` rejects other values of each, and `to_yaml` round-trips them.
1. `stack:` holds `language, frameworks, front_end, persistence, caching, logins, deployment, domain, from, to` (research shape, `.openlanes.yml`).
1. A stack detector maps marker files to a stack (`Gemfile`, `package.json`, `go.mod`, `Cargo.toml`, `mix.exs`, `pyproject.toml`/`requirements.txt`, with the refinements listed in `## Research`), tested on real temp folders. A folder with two language markers reports as mixed, and the interview asks.
1. `init` writes `docs/decisions/stack.md` from the same fields; absent when the stack is unknown and `-y` is used.
1. Interview order is merge, build quality, stack; the existing four values remain.
1. Free-text "Describe the app you want to build" with extraction through `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`; answered questions are skipped. With neither key, one message, then every question is asked. No placeholder answers are ever filled in.
1. When a stack is detected and the user is open to alternatives, ask "port the code or start fresh beside it"; a port writes `stack.from` and `stack.to`.
1. `init -y` takes flags and defaults for the new keys, asks nothing and makes no network call. New flags: `--merge-by`, `--build-quality`.
1. `init --reconfigure` loads the current file as defaults, prints what changed and writes only after confirmation (`-y` skips it, `-n` previews).
1. `rubocop` at zero offenses and `rspec` green, with the extraction adapter injected as a double (the suite never reaches the network).

## Out of scope

- Cmd-Backspace "go back": needs a per-terminal key test (research, unsettled 1) and an engine `back` that does not exist (M17.5). Reason: depends on upstream work.
- Rewriting existing `.openlanes.yml` keys beyond the three new ones. Reason: not needed.
- Linear/GitHub sync of the stack. Reason: no consumer yet.

## Back end / front end

`luke-backend` builds everything in scope. `rey-frontend` has no work here: `init` is a terminal command and the web Settings dialog is v2.0 (M19). The pair's only shared surface is the config keys, which the control room may read later.

| Item | Half |
| --- | --- |
| Config keys, validation, yaml round-trip | luke-backend |
| Stack detector | luke-backend |
| Interview flow, `-y`, `--reconfigure` | luke-backend |
| Extraction adapter selection | luke-backend |
| `stack.md` writer | luke-backend |
| Any web surface | none (v2.0) |

## Open questions

Unsettled items from the research, and what had to be assumed. None is answered here.

1. **inquirex pin.** `inquirex-tty` 0.10.0 pins `inquirex ~> 0.9.5` while the local checkout is 0.10.0; Bundler resolution was never run. Options: wait for the upstream fix (M17.1), pin 0.9.x, or keep tty-prompt for the flow and use inquirex-llm only for extraction. Recommendation: build the detector, config and `-y` path now (they do not depend on it), and take the flow on whichever pin resolves.
1. **Back navigation.** Replay `history`, or add `back` upstream? Does iTerm2/Terminal.app deliver Cmd-Backspace? Treated as out of scope.
1. **Mixed-stack default.** Which marker is the default answer when two languages are present? Assumed: no default, the question is asked; under `-y` the stack is left unset.
1. **Marker list.** The detection table is a research proposal, not a repo definition. Does it need a Java or .NET marker?
1. **`merge.by` and `-y`.** What does `-y` choose? Assumed `human` (M4 states no default).
1. **`build_quality` default under `-y`.** Assumed `high`; M5 states no default.
1. **Default model for extraction.** `claude-sonnet-4-20250514` is outdated (M17.2); which model id does openlanes pass? Assumed to be an openlanes config value, not hard-coded.
1. **Does `docs/decisions/stack.md` get overwritten** on `--reconfigure`, or is a new dated section appended? Assumed: overwritten, shown in the diff.
1. **Stack field vocabulary.** Free text or a closed list for `frameworks` and `persistence`? Assumed free text, validated as non-empty strings.
1. **OpenAI.** M16 names `OPENAI_API_KEY`; is an OpenAI adapter in `inquirex-llm` verified? Not checked.

## Risks to planning or execution

- The dependency conflict (question 1) can block the interview flow; work units must keep the data model and detector independent of it.
- `Config.parse` rejects unknown keys, so a newer `.openlanes.yml` is refused by an older openlanes. Acceptable, but release notes must say so.
- Extraction is nondeterministic and networked; specs must use a recorded or injected adapter, and the live path needs an eval, not a unit test.
- `Config::KEYS` is read by `Base.default_params`; adding nested hashes (`merge`, `stack`) may collide with the flat shorthand mapping (`SHORTHANDS`), which has not been read to the end.
- Plan 010 is a dependency (`depends_on`); its contents were not re-read here.

## Conclusion

`openlanes init` will write `merge.by`, `build_quality` and `stack` to `.openlanes.yml`, plus `docs/decisions/stack.md`, from flags (`-y`) or a terminal interview that detects the existing stack, extracts answers from a description when a key is present, and records a port. `--reconfigure` re-runs it and shows the diff. Execution of merges, quality tiers, ports and the web widget remain later plans.

## Research

Method: one pass over the `011.00` worktree and the local inquirex checkout at `/Users/kig/github/inquirex`. No web search: every question was settled by reading code or gemspecs. Baseline: `bundle exec rspec` on Ruby 4.0.6 reports 2214 examples, 0 failures (observed 2026-10-13).

### Stack detection: which files identify which stacks

Nothing detects stacks yet. The only file-based detection is `Execution::Checks`, which reads `justfile` and `Gemfile` to pick a test command (`lib/openlanes/execution/checks.rb:41`).

Proposed markers. This is a design proposal, not something the repo already defines:

- `Gemfile` → Ruby; `rails` or `sinatra` in `Gemfile.lock` refines it.
- `package.json` → Node/TypeScript; `react`, `astro`, `vite` or `next` in its dependencies refine it.
- `astro.config.*`, `vite.config.*` → front end hints.
- `go.mod`, `Cargo.toml`, `mix.exs` → Go, Rust, Elixir.
- `pyproject.toml` or `requirements.txt` → Python; `fastapi` or `django` refine it.
- `Dockerfile`, `.tool-versions` → deployment and version hints only.

A folder with two language markers is a mixed stack. The questionnaire asks; it does not guess.

### The questionnaire as an inquirex flow

- The DSL exists: `Inquirex.define id:, version:` with `ask :key do ... end` (`inquirex-tty/examples/05_job_application.rb:12-24`). Questions are skipped with `skip_if not_empty(:key)` (`inquirex-tty/lib/inquirex/tty/commands/run.rb:70`), which is how extracted answers would drop questions.
- **Version conflict.** Local `inquirex` and `inquirex-llm` are 0.10.0 (`inquirex/lib/inquirex/version.rb:4`). `inquirex-tty` 0.10.0 requires `inquirex ~> 0.9.5` and `inquirex-llm ~> 0.9.5` (`inquirex-tty/inquirex-tty.gemspec:37-38`). The gem installed here is 0.9.4. Bundler was not run on this combination.
- **No back.** The engine keeps `history` (`inquirex/lib/inquirex/engine.rb:14`, `:65`) but defines no method to step back. A grep for `def back|undo|rewind|previous|go_back` in `inquirex/lib` finds none.
- **No non-interactive mode.** `inquirex-tty` has no `--yes` or stdin mode. Its only prefill is `engine.prefill!`, used by its `run` command (`run.rb:70-78`). `init -y` must therefore be handled in openlanes.
- **Adapters.** `Inquirex::LLM::NullAdapter` fills placeholder answers (`inquirex-llm/lib/inquirex/llm/null_adapter.rb:18`), which M16 forbids. openlanes must pick the adapter itself. The Anthropic default model is `claude-sonnet-4-20250514` (`inquirex-llm/lib/inquirex/llm/anthropic_adapter.rb:29`), the outdated id M17 names.
- **Current `init` uses no inquirex.** `lib/openlanes/cli/init/init.rb:3` requires `tty-prompt`. It asks four values (project, lane, frontend, jobs) and takes flags for each.

### The stack summary and `docs/decisions/stack.md`

- Neither exists. `docs/decisions/stack.md` is absent. `Config::KEYS` (`lib/openlanes/support/config.rb:84`) holds no `stack` key, and `Config.parse` rejects unknown keys.
- Proposed shape, for yoda to confirm. `.openlanes.yml` gets the summary; `docs/decisions/stack.md` gets the same fields in prose:

  ```yaml
  stack:
    language: ruby
    frameworks: [sinatra]
    front_end: react
    persistence: postgres
    caching: redis
    logins: none
    deployment: null
    domain: null
    from: null   # set by M18 when porting
    to: null
  ```

### Contradictions

| Source | Says | Code | Production runs |
| --- | --- | --- | --- |
| `spec.md` "How to tell it's working", M4 and M5 (`docs/decisions/decisions-on-merge-modes-and-verification.md:42,52`) | `.openlanes.yml` holds `merge.by`, `build_quality`, `stack` | `Config::KEYS` rejects all three (`config.rb:84`) | The code. The decisions are unbuilt. |
| M16 (same file, `:152-159`) | `lanes init`, inquirex-tty, `--reconfigure` | `openlanes init` (`init.rb:12`), tty-prompt, `--overwrite` only; `--reconfigure` appears only in the decision file | The code: tty-prompt, no reconfigure. |
| M16 | inquirex-tty for the interview | No `inquirex` in `openlanes.gemspec` or `Gemfile` | The code: no inquirex. |

### Could not settle

1. Does iTerm2 and Terminal.app deliver Cmd-Backspace to a Ruby program? Needs a key test in each terminal. M16 asks for it.
2. Which inquirex pin to use, since 0.10.0 conflicts with `inquirex-tty` 0.10.0. Needs a decision, or an upstream release. Bundler resolution not run.
3. How back works: replay `history`, or add a `back` upstream in inquirex. Design choice.
4. Mixed-stack folders: which of the two markers wins as the default answer. Design choice, for the owner.

### Findings, Conclusion & References

Findings:

- Stack detection, the inquirex flow and the stack summary are all unbuilt. Only the decisions exist.
- By the gemspecs, the inquirex stack cannot install as M16 describes: `inquirex-tty` 0.10.0 pins `inquirex` below 0.10. Bundler has not confirmed this.
- `init` needs its own `-y` path, since the gem has none.

Conclusion: yoda can write Goal, Non-Goals, scope and open questions from this chapter without asking. The decision to adopt inquirex for `init` and the pin to use are still open, listed above.

References (local, retrieved 2026-10-13):

- `lib/openlanes/cli/init/init.rb`, `lib/openlanes/support/config.rb`, `lib/openlanes/execution/checks.rb`
- `docs/decisions/decisions-on-merge-modes-and-verification.md`
- `/Users/kig/github/inquirex` (inquirex 0.10.0, inquirex-tty 0.10.0, inquirex-llm 0.10.0). Source is local and not copied here; no licence concern.

> [!NOTE]
>
> [2026-10-13 07:27:19 PM PDT] [ agent: yoda-writer   status: **Interrupted, round 1 (interrupted, killed 60s after q)** ]
