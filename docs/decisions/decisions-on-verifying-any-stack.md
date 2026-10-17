# Decisions on verifying any stack

Decided 2026-10-17 by the owner (kig). Grilling session, one question at a time, measured against M0 in [decisions-on-agent-memory-and-sessions.md](decisions-on-agent-memory-and-sessions.md): a person intervenes as rarely as possible.

chewie-verifier (plan 014) was first built to verify through the shell alone: `curl` against the app's ports, and text captures rendered to PNG as screenshots. That suits a CLI or a library, such as openlanes itself, and falls short for any project with a UI. Starting an app and testing it differs on every stack, and between projects on the same stack, so everything stack-specific is declared by the project in `.openlanes.yml`, never assumed by the gem.

Amends M14 (screenshots) in [decisions-on-merge-modes-and-verification.md](decisions-on-merge-modes-and-verification.md).

### V1. chewie drives a real browser through Playwright MCP

- For a project with a web app, chewie gets the Playwright MCP server's tools (navigate, click, fill, screenshot) and walks the PR's `## How to test` in a real, headless browser.
- It may reach only the URLs of the app the engine started (`app.md`), on localhost. Nothing else on the network.
- Screenshots are real PNGs from the browser, replacing the text captures rendered with `magick`. The text captures stay for steps that run through the shell (a CLI, a `curl`).

### V2. `app.setup` runs before every start

```yaml
app:
  setup:
    - bundle install
    - bin/rails db:prepare
  processes:
    - name: web
      start: bin/rails server -p $PORT_WEB
```

- A list of commands, run in order in the PR's checkout before the processes start, every time the app starts, so a migration added in a later commit is never missed.
- Making them idempotent is the project's job.
- A command that fails rejects the verification with its last 20 lines, as a process that fails to start does.

### V3. `verify.e2e` runs the project's own suite first

```yaml
verify:
  e2e: npx playwright test
```

- Optional. When present, the engine runs it against the started app, with `PORT_<NAME>` and `APP_URL` in its environment, before chewie walks How to test.
- A failure rejects with the tail of the suite's output and any screenshots the suite wrote. Only after it passes does chewie walk How to test.
- Without it, How to test alone is verified.

### V4. A missing `app:` is decided by kind

- `app.kind: cli` and `app.kind: library` declare a project with nothing to start: they need no `processes:`, and chewie verifies through the shell.
- A project with no `app:` section at all is sent back to luke, uncounted against `merge.max_rejections`, to declare one, exactly as a missing `coverage:` section is (the M15 amendment). `app: { kind: cli }` is a complete answer for a project with nothing to run.
- The silent shell-only fallback is removed: a web app is never "verified" without having been started.
