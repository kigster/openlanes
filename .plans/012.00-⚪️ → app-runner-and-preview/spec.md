---
depends_on: []
---

# App Runner and Preview

## What we are trying to achieve

The engine starts the app a plan builds, from `app.processes` in `.openlanes.yml`, gives each process a port from 11100, restarts it when its `restart_on` files change, and shows it in a Preview tab.

## Why it matters

Verification (M1) and a human checking a PR both need the app running, whatever its stack.

## What already exists

- Decisions M12 and M13 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.
- `lib/openlanes/execution/child.rb` for processes, the web control room in `web/`.

## What research needs to settle

- Readiness checks, port allocation and per-checkout isolation.
- Detecting an app that refuses to be framed.
- Mirroring a headless browser into the tab.

## How to tell it's working?

- A two-process app (API and web) starts in order; the tab shows the web process, labelled with plan, branch and port.
- Editing a `restart_on` file restarts only that process, and the toolbar says so.
- A framing-protected app opens in a separate window.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

