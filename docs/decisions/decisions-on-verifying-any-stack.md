# Decisions on verifying any stack

Decided 2026-10-17 by the owner (kig). Grilling session, one question at a time, measured against M0 in [decisions-on-agent-memory-and-sessions.md](decisions-on-agent-memory-and-sessions.md): a person intervenes as rarely as possible.

chewie-verifier (plan 014) was first built to verify through the shell alone: `curl` against the app's ports, and text captures rendered to PNG as screenshots. That suits a CLI or a library and falls short for anything with a UI, whether in a browser, in a terminal or on a desktop. How an app is set up, run, linted, tested and driven differs on every stack, and between projects on the same stack, so all of it is declared by the project in the `app:` section of `.openlanes.yml`, never assumed by the gem.

Amends M14 (screenshots) in [decisions-on-merge-modes-and-verification.md](decisions-on-merge-modes-and-verification.md).

### V1. The `app:` section says how to set up, run, lint and test

```yaml
app:
  kind: web              # web | tui | cli | desktop | library
  driver: browser        # optional; the kind's default otherwise (V2)
  setup:                 # make sure the environment is ready
    - bin/setup
  run: bin/dev           # run the latest version, from this checkout
  processes: [...]       # instead of run:, when several long-running processes make up the app
  lint: just lint
  test: just test
  check: just ci         # one command for linters and the whole suite; used instead of lint and test
```

- `kind` is required. `run` or `processes` is required for every kind but `library`.
- `lint` and `test` are each optional, but the project must have something that fails when the program breaks: `test` or `check`. A linter alone is not that. Before chewie walks How to test, the engine runs `check`, or else `lint` (when given) and then `test`, in the PR's checkout, against the started app, with `PORT_<NAME>` and `APP_URL` in the environment. A failure rejects with the tail of its output and any screenshots it wrote. The project's own end-to-end suite belongs in `test` or `check`; it replaces the separate `verify.e2e` decided earlier the same day.
- `setup` is a list of commands run in order before every start, so a migration added in a later commit is never missed. Making them idempotent is the project's job. A command that fails rejects with its last 20 lines, as a process that fails to start does.
- `coverage:` stays its own section (the M15 amendment).

### V2. The kind picks how chewie drives the app; `driver:` may override it

| Kind | Default driver | chewie walks How to test through | Screenshots |
| --- | --- | --- | --- |
| `web` | `browser` | a headless browser (Playwright MCP), limited to the started app's localhost URLs | the browser's PNGs |
| `tui` | `terminal` | a terminal it controls: tmux `send-keys` in, `capture-pane` out | the pane rendered to PNG |
| `cli` | `shell` | the shell | the output rendered to PNG |
| `desktop` | `person` | nothing: see V3 | none |
| `library` | `none` | nothing: `check` (or `lint` and `test`) is the whole verification | none |

- The gem ships these drivers. A project whose app does not fit its kind's default names another with `driver:`, without new code.
- A driver reaches only the app the engine started, never anything else on the network.

### V3. A desktop app is tested automatically and walked by a person, for now

- The engine runs `check`, or `lint` and `test`, including the project's own UI tests, as for every kind.
- Walking How to test goes to a person as one question listing the steps; their answer is the verdict. A desktop driver can come later.

### V4. `openlanes init` detects, then confirms each answer

- init reads the repository (justfile and Makefile targets, `package.json` scripts, `bin/setup`, `bin/dev`, `Procfile`, `Gemfile`, `Cargo.toml` and the like) and proposes every key of V1, with its guess as the recommended answer, one question at a time. The person accepts or types their own.
- Nothing is written that the person did not confirm (M0, M6).
- init asks separately whether the project already has a test suite and whether it has a linter, and for the command of each it has.
- For each it lacks, init asks whether to add one. A yes creates it as the project's first plan (a test suite, or a linter, for this stack), and every plan created after it depends on it, so nothing is built before there is something that fails when the program breaks. That plan writes `test:` (or `lint:`) into `app:` when it lands.
- A no to a test suite leaves the project without what V1 requires, so its PRs go back to luke under V5 until one exists.

### V5. A missing or incomplete `app:` goes back to luke

- A project with no `app:` section, or one missing a key V1 requires, is sent back to luke, uncounted against `merge.max_rejections`, to declare it, exactly as a missing `coverage:` section is.
- There is no silent shell-only fallback: an app is never "verified" without having been started the way the project says.

### V6. The init interview is an inquirex flow

- The questionnaire of V4 is an inquirex flow instead of hand-built `TTY::Prompt` calls. Three gems, each with one job:
  - [`inquirex`](https://github.com/inquirex/inquirex): the DSL (`Inquirex.define`, `ask`, `say`, `default`, `transition ... if_rule:`) and the engine that walks the flow.
  - [`inquirex-tty`](https://github.com/inquirex/inquirex-tty): the terminal widgets that render each step (`select`, `multi_select`, text input).
  - [`inquirex-llm`](https://github.com/inquirex/inquirex-llm): the `extract` step, which has an LLM turn free text into structured answers.
- openlanes depends on `inquirex-llm` today, and gets `inquirex` through it; `inquirex` and `inquirex-tty` become direct dependencies.
- It follows the shape of inquirex-tty's `examples/10_real_tax_preparer.rb`:
  1. A short `say` explains what is being set up.
  2. An optional free-text `ask :describe`: what the app is, how it is run, tested and linted, in the person's own words.
  3. An `extract` step reads that description, together with what init detected in the repository (V4), into a schema built from the questions below (`kind`, `setup`, `run`, `lint`, `test`, `check`, whether there is a test suite, whether there is a linter). The schema is derived from the ask steps, so the option lists are written once.
  4. One `ask` per key. Unlike the example, none is skipped with `skip_if not_empty`: each is pre-filled with `default { ... }` from the extraction, or else from detection, and the person confirms or changes it (V4: nothing written unconfirmed).
  5. `has_test_suite` and `has_linter` branch, with `transition ... if_rule:`, to "add one as the first plan?" (V4).
- Without an LLM key, or when the person skips `:describe`, the extract step is skipped and the defaults come from detection alone; the interview still works.
