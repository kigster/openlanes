---
created: 2026-10-24
starts: research
depends_on: ["011.00", "045.00"]
---

# Ol Init Done Properly

## What we are trying to achieve

The `ol init` interview adds the adapter and model per phase, turns pushing off when there is no `origin` remote, a `telemetry:` section, `app:` processes when the stack has a runnable app, and coverage (command, report, format, minimum, detected from the stack, default 95). `.openlanes.yml` is written with a comment above every key. `ol init --check` validates an existing file (A16). The stale `.openlanes.coverage.yml` is deleted.

## Why it matters

Most of `.openlanes.yml` is invisible to a new user, and coverage is never asked, so the gate is off by default.

## What already exists

`lib/openlanes/setup/interview.rb`, `lib/openlanes/support/config.rb` (18 keys), `lib/openlanes/coverage/config.rb` with its legacy warning, and plan 011.00 init-interview, still building.

## What research needs to settle

- How comments survive `--reconfigure` round trips.
- Which stacks' coverage tools can be detected reliably.
