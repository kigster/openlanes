# Plan 010.00, front end (frontend-coder)

Repository root: `/Users/kig/github/inquirex`. Paths below are relative to it. The front end is the terminal UI and CLI of `inquirex-tty`. Branch `kig/010.00-inquirex-fixes` in each repository you touch, and run `alock` inside it. Order and assumptions: see `plan.md`.

## F1 Ctrl-B back in the TTY renderer

- **Discipline:** front end.
- **Owns:** `inquirex-tty/lib/inquirex/tty/renderer.rb`, `inquirex-tty/lib/inquirex/tty/back_key.rb` (new, if the chosen interrupt needs its own class), `inquirex-tty/spec/inquirex/tty/renderer_back_spec.rb` (new).
- **Must not touch:** `inquirex/**` (ask B3 for engine changes), `inquirex-tty/lib/inquirex/tty/commands/run.rb` (F2), any README (F3).
- **Depends on:** B1, B3.
- **What:** Ctrl-B (`:ctrl_b`, mapped by `tty-reader` 0.9.0, unbound in `tty-prompt` 0.23.1) calls `Engine#back` while any collecting prompt is open, then re-asks the previous question with `Engine#previous_answer` as its default. When `can_back?` is false the key does nothing. The tip line names the key ("Ctrl-B: back"). How `select`, `multi_select` and `ask` are aborted (prompt subclass or raise from the keypress handler) is yours to choose; record the choice and why in the spec file's top comment, and hand F3 the one README line naming the key.
- **Done when:** `renderer_back_spec.rb` drives the renderer with a fake prompt that emits `:ctrl_b` on the second question, and asserts the engine is back on the first step, the first question is re-asked with its answer as default, and `:ctrl_b` on the first question changes nothing. `renderer_spec.rb` stays green.

## F2 `run --answers`, `--yes`, results on stdout; integration check

- **Discipline:** front end.
- **Owns:** `inquirex-tty/lib/inquirex/tty/commands/run.rb`, `inquirex-tty/lib/inquirex/tty/output_path.rb`, `inquirex-tty/lib/inquirex/tty/answers_file.rb` (new), `inquirex-tty/spec/inquirex/tty/commands/run_spec.rb`, `inquirex-tty/spec/inquirex/tty/output_path_spec.rb`, `inquirex-tty/spec/inquirex/tty/answers_file_spec.rb` (new), `inquirex-tty/spec/integration/headless_run_spec.rb` (new), `inquirex-tty/spec/fixtures/headless/**` (new).
- **Must not touch:** `renderer.rb` (F1), `inquirex/**` (B3, B4), any README (F3).
- **Depends on:** B1, B4.
- **What:**
  - `inquirex-tty run FLOW [--answers FILE] [--yes] [-o [FILE]]`.
  - `AnswersFile.load(path) -> Hash`: JSON or YAML by extension, `{step_id: value}`; anything else is a clear error.
  - With `--answers` or `--yes`, the command uses `Inquirex::Headless` (B4) and never builds a `TTY::Prompt` or `Renderer`. `MissingAnswer` exits non-zero with the step id on stderr.
  - Results JSON goes to stdout by default (moved from stderr, `run.rb:25`); `-o FILE` writes the file; `-o -` is stdout. Interactive rendering stays on stderr.
  - Hand F3 the replacement text for README `:66` and `:78`.
- **Done when:**
  - `run_spec.rb` captures stdout and stderr separately and parses stdout as JSON, for both the interactive and headless paths; asserts `TTY::Prompt` is never instantiated with `--answers` or `--yes`.
  - `answers_file_spec.rb` covers JSON, YAML and an unknown extension.
  - **Integration check**, `spec/integration/headless_run_spec.rb`: spawns the real `exe/inquirex-tty run` as a child process with STDIN closed, nothing stubbed, the real engine from the local path, against a fixture flow with a multi-select, a defaulted step and a `skip_if` on the multi-select. It must show: `--answers` exits 0 with every answer in stdout JSON and none on stderr; `-o FILE` writes the same JSON and leaves stdout empty; `-o -` writes stdout; `--yes` with an undefaulted required step exits non-zero naming it.

## F3 READMEs and the Ruby 4.1.0-preview1 record

- **Discipline:** front end.
- **Owns:** `inquirex/README.md`, `inquirex-llm/README.md`, `inquirex-tty/README.md`, `verification.md` in this plan folder (new).
- **Must not touch:** any `lib/`, `spec/`, gemspec, Gemfile or CHANGELOG.
- **Depends on:** F1, F2.
- **What:**
  - Replace the sample answers at `inquirex-tty/README.md:97-98` and `:217-220` with fictional ones (`Ada Example`, `ada@example.com`). Copyright lines stay (spec OQ4). Check `~/.agents/context/forbidden-identities.md` for the names to search for.
  - `inquirex-tty/README.md:66` and `:78` state the results channel exactly as F2 built it, and document `--answers`, `--yes` and `-o -`.
  - One line naming Ctrl-B as the back key, from F1.
  - Run `inquirex-tty`'s specs on Ruby 4.1.0-preview1 without Bundler's path source (e.g. `ruby -Ilib -I../inquirex/lib -I../inquirex-llm/lib -S rspec`), and `bundle exec rspec` in `inquirex` and `inquirex-llm` on 4.1.0-preview1. Write the commands, example counts and failures, or the Bundler-only failure, to `verification.md`.
- **Done when:** `rg` for the forbidden names and emails across the three READMEs matches only copyright lines; `verification.md` holds the three 4.1.0-preview1 results; `bundle exec rspec` in `inquirex-tty` stays green on 4.0.x.
