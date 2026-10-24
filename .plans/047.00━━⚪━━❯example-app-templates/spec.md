---
created: 2026-10-24
starts: research
---

# Example App Templates

Decided with the owner (kig) on 2026-10-24; see `docs/decisions/decisions-on-example-apps.md` (E1 to E3, E7).

## What we are trying to achieve

Three templates in a new repository, `kigster/openlanes-examples`, one top-level folder each (E1, E2): a SwiftUI menu-bar clipboard history built with SwiftPM, a Rust `logtail` CLI that follows and filters JSON logs, and a Rails habit tracker with streaks. Each holds a `README.md`, `.plans/APPLICATION.md` (goals and non-goals), a skeleton that compiles, and a few ⚪ seed plans (E3) and a `.openlanes-template` marker. Each README follows `docs/STARTING-AN-APP.md` and links to it (E7). A new command, `ol new --example <name> <dir>`, sparse-clones the repository, copies one template out, drops the marker, runs `git init` and `ol init -y`, and with `--github` (asked first) runs `gh repo create`. Then `cd <dir> && ol start` builds the app.

## Why it matters

It shows the factory working on stacks other than Ruby, gives the init interview's CI and stack detection real inputs, and supplies end-to-end eval projects that start clean on every try.

## Task completed when

- `ol new --example rust-logtail /tmp/x` then `ol start --until-settled --no-git-push` in `/tmp/x` advances at least one seed plan.
- `ol start` refuses in a folder carrying `.openlanes-template`; no template has a `.openlanes.yml` until copied.
- `ol new` warns when the installed gem is older than the template's minimum version.
- `ol new --example` without a name lists the templates.

## How to verify

Specs for `ol new` against a local bare clone of the examples repository, offline. The examples repository's own CI runs the first criterion per template; `macos-clipboard` on a macOS runner, its GUI checked by hand.

## What already exists

- `lib/openlanes/cli/init/init.rb` and `lib/openlanes/setup/interview.rb`: what `ol new` runs after copying.
- `lib/openlanes/support/project.rb`: the root search the marker check belongs next to.
- No `ol new` command and no examples repository yet.

## What research needs to settle

- Sparse clone or a release tarball from GitHub for `ol new`, and what it does offline.
- Where a template declares its minimum openlanes version.
- Which seed plans each template ships, and the smallest skeleton that still compiles.
