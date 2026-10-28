---
created: 2026-10-27
starts: planning
depends_on: ["056.00", "057.00"]
---

# Project Settings Page

Source: the user, 2026-10-27, split out of plan 056 (S6). Decisions S1, S2 and S5 were settled there and are copied here unchanged.

## What we are trying to achieve

1. **A Project settings page** in the control room, the third item in the nav plan 056 builds: `Board | Plan dependencies | Project settings`, at `/settings`.
2. **A friendly form over `.openlanes.yml`**, rendered from plan 057's schema: every key with its value or default, a field type per key (text, number, toggle, select), and its help line.
3. **Save, commit and push to main**, in one step, so every worktree gets the change.

## Why it matters

Today a person learns what `.openlanes.yml` can hold by reading `config.rb`'s comment, and changes it by hand-editing YAML. The page shows every setting there is and changes one safely.

## Decisions (2026-10-27)

- **S1, how a save lands:** Save writes `.openlanes.yml` in the main checkout, commits it and pushes it to `main`, in one step, so every worktree created or rebased afterwards gets the new settings. The button says so: **Save, commit and push to main**, and the page states it beside the button. Nothing changed, nothing written. (Replaces an earlier answer that routed the change through a `starts: building` plan.)
- **S1, constraints for planning:**
  - `Config.parse` accepts the new values before anything is written; a refused value is shown on its field.
  - The push is the harness's, not an agent's, so it is declared through `Boundary.sanction` first; otherwise an agent running at that moment is blamed for a moved `origin/main`.
  - The save refuses, saying why, when the main checkout is not on `main`, when `.openlanes.yml` has uncommitted edits, or when `main` cannot fast-forward to `origin/main`.
- **S2, layout:** the page mirrors the file, with no invented groups. The top-level scalar keys (`project`, `starts`, `jobs`, …) share the first pane; every top-level section (`merge`, `coverage`, `ci`, `stack`, `app`, `events`, `redis_backoff`, `commands`, …) gets a pane of its own, in the order `Config::KEYS` lists them. Every pane is open on load, so the whole file is visible at once, as in Cursor's settings; a − in a pane's header collapses it and a + opens it again.
- **S5, the `commands:` pane:** one sub-pane per command, with the options that command declares (from 057's generated schema).

## What already exists

- Plan 056: the SPA's top nav and path routing. Plan 057: the schema, the full-file writer, the main-checkout start.
- `POST /api/commands` reaches `Live::Commands`; the page's other actions already go that way.
- `Boundary.sanction`, which declares a push the harness makes itself.

## How to tell it's working?

- The page lists every key in the schema, each pane open, each collapsible with −/+.
- A refused value is shown on its field and nothing is written.
- Save with no change writes nothing; with a change it writes, commits and pushes `main`, and the board's next snapshot reads the new value.
- Each refusal in S1's constraints is shown with its reason.
- Component tests for the form and the panes; a Cypress test that edits a value and saves against a temp repo with a bare remote.
