# Plan 010.00, back end (luke-backend)

Repository root: `/Users/kig/github/inquirex`. Paths below are relative to it. Each of `inquirex/`, `inquirex-llm/`, `inquirex-tty/` is its own git repository; branch `kig/010.00-inquirex-fixes` in each one you touch, and run `alock` inside it. Order and assumptions: see `plan.md`.

## B1 Version alignment at 0.11.0

- **Discipline:** back end.
- **Owns:** `inquirex/lib/inquirex/version.rb`, `inquirex-llm/lib/inquirex/llm/version.rb`, `inquirex-tty/lib/inquirex/tty/version.rb`, `inquirex-llm/inquirex-llm.gemspec` (only if it constrains `inquirex`), `inquirex-tty/inquirex-tty.gemspec`, `inquirex-tty/Gemfile`, `inquirex-tty/Gemfile.lock`, `inquirex-llm/Gemfile`, `inquirex-llm/Gemfile.lock`, `inquirex-tty/spec/inquirex/tty_spec.rb`.
- **Must not touch:** any `lib/` file other than the version files, any README or CHANGELOG.
- **Depends on:** nothing.
- **What:** all three `VERSION` constants become `0.11.0`. `inquirex-tty.gemspec:37-38` require `inquirex ~> 0.11` and `inquirex-llm ~> 0.11`. `inquirex-tty/Gemfile` replaces the `INQUIREX_VERSION` rubygems pin with `path: "../inquirex"` and `path: "../inquirex-llm"` so the front-end units build against the local engine; the lock is regenerated.
- **Done when:** `bundle exec rspec` passes in all three gems, and `inquirex-tty/spec/inquirex/tty_spec.rb` gains an example asserting `Gem.loaded_specs["inquirex"].version >= Gem::Version.new("0.11.0")`.

## B2 Current Claude model ids

- **Discipline:** back end.
- **Owns:** `inquirex-llm/lib/inquirex/llm/anthropic_adapter.rb`, `inquirex-llm/spec/inquirex/llm/anthropic_adapter_spec.rb`.
- **Must not touch:** the other adapters, any version file, any README.
- **Depends on:** nothing.
- **What:** one constant, `AnthropicAdapter::MODELS` (frozen list of current ids: `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-fable-5-1`). The default (`:29`) and every alias value (`:40-42`) are drawn from it, not written beside it.
- **Done when:** `anthropic_adapter_spec.rb` asserts the default and each alias value is in `MODELS`; `rg 'claude-sonnet-4-20250514|claude-.*-4-' inquirex-llm` returns nothing.

## B3 `Engine#back` snapshot stack

- **Discipline:** back end.
- **Owns:** `inquirex/lib/inquirex/engine.rb`, `inquirex/spec/inquirex/engine_back_spec.rb` (new).
- **Must not touch:** `inquirex-tty/**`, `inquirex/lib/inquirex/headless.rb` (B4).
- **Depends on:** B1.
- **What:** `answer`, `skip` and `advance` push `to_state` (`engine.rb:270`) onto a private snapshot stack before they mutate. Public surface:
  - `Engine#back -> Boolean`: restores, via `restore_state` (`:316`), the latest snapshot whose `current_step_id` is a collecting step; returns `false` and changes nothing at the first collecting step.
  - `Engine#can_back? -> Boolean`.
  - `Engine#previous_answer(step_id) -> Object | nil`: the answer to pre-fill after `back`.
  - The stack survives `to_state`/`restore_state` round trips or is explicitly excluded from them; decide, and say which in a YARD note.
- **Done when:** `engine_back_spec.rb` compares whole `to_state` hashes before the undone step and after `back` (answers, totals including `:text`, skipped, suggestions, history), across: a Proc default, a `prefill!`-derived suggestion, an accumulator step, a display step between two questions (back skips it), and `back` at the first step returning `false`.

## B4 Headless answer driver in core

- **Discipline:** back end.
- **Owns:** `inquirex/lib/inquirex/headless.rb` (new), `inquirex/spec/inquirex/headless_spec.rb` (new).
- **Must not touch:** `inquirex/lib/inquirex/engine.rb` (B3 owns it; if B4 needs an engine method, B3 adds it first), `inquirex-tty/**`.
- **Depends on:** B3.
- **What:** `Inquirex::Headless.new(definition, answers: Hash, yes: Boolean).call -> Hash` (the results `inquirex-tty` serialises). It feeds the engine through `answer` and `skip` only, never `prefill!`. Display steps advance silently. With `yes: true`, a step absent from `answers` takes its default; an LLM step is skipped with its default and no adapter is called. A required step with neither raises `Inquirex::Headless::MissingAnswer` carrying `step_id`. It never touches `$stdin` or a prompt.
- **Done when:** `headless_spec.rb` covers a multi-select with a `skip_if` on it (the `prefill!` hang the research found), a Proc default under `yes: true`, an LLM step under `yes: true` with an adapter double that fails the example if called, and `MissingAnswer` naming the step.

## B5 Release: CHANGELOGs, constraint check, scratch bundle

- **Discipline:** back end.
- **Owns:** `inquirex/CHANGELOG.md`, `inquirex-llm/CHANGELOG.md`, `inquirex-tty/CHANGELOG.md`, `inquirex-tty/Gemfile`, `inquirex-tty/Gemfile.lock`, `inquirex-llm/Gemfile`, `inquirex-llm/Gemfile.lock`.
- **Must not touch:** any `lib/` or `spec/` file, any README.
- **Depends on:** B2, F3 (and so, transitively, every other unit).
- **What:** a `0.11.0` entry in each CHANGELOG naming that gem's changes, and in `inquirex-tty`'s the stdout move as a breaking change for callers reading stderr; each cites the Ruby 4.1.0-preview1 result from `verification.md` in this plan folder. Decide whether `inquirex-tty/Gemfile` keeps the local `path:` sources from B1 or returns to `~> 0.11` from rubygems for release, and record the choice in the CHANGELOG. Install all three at 0.11.0 in a scratch Gemfile (path sources) outside the repos.
- **Done when:** the scratch `bundle install` succeeds and its command and output are appended to `verification.md`; `bundle exec rspec` is green in all three; the three `VERSION` constants and the `inquirex-tty.gemspec` constraints agree (B1's `tty_spec.rb` example still passes).
