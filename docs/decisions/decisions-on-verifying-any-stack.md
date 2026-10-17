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
- Either `check`, or both `lint` and `test`, is required. Before chewie walks How to test, the engine runs `check` (or `lint`, then `test`) in the PR's checkout, against the started app, with `PORT_<NAME>` and `APP_URL` in the environment. A failure rejects with the tail of its output and any screenshots it wrote. The project's own end-to-end suite belongs in `test` or `check`; it replaces the separate `verify.e2e` decided earlier the same day.
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

- The engine runs `check` (or `lint` and `test`), including the project's own UI tests, as for every kind.
- Walking How to test goes to a person as one question listing the steps; their answer is the verdict. A desktop driver can come later.

### V4. `openlanes init` detects, then confirms each answer

- init reads the repository (justfile and Makefile targets, `package.json` scripts, `bin/setup`, `bin/dev`, `Procfile`, `Gemfile`, `Cargo.toml` and the like) and proposes every key of V1, with its guess as the recommended answer, one question at a time. The person accepts or types their own.
- Nothing is written that the person did not confirm (M0, M6).

### V5. A missing or incomplete `app:` goes back to luke

- A project with no `app:` section, or one missing a key V1 requires, is sent back to luke, uncounted against `merge.max_rejections`, to declare it, exactly as a missing `coverage:` section is.
- There is no silent shell-only fallback: an app is never "verified" without having been started the way the project says.
