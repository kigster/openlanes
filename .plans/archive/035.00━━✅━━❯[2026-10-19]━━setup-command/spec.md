---
created: 2026-10-17
starts: planning
---

# Setup Command

## What we are trying to achieve

An `openlanes setup` command that gets a machine ready to run the factory, from any directory:

- Runs `brew bundle --no-upgrade --file <gem root>/Brewfile`, where the gem ships a `Brewfile` of the tools openlanes needs at runtime: at least `git`, `gh`, `redis`, `just` and `imagemagick` (verifier renders screenshots with `magick`), plus whatever else the engine and agents shell out to. The list is derived by checking the code, not guessed.
- Then checks what brew cannot install: the `claude` CLI is on `PATH`, `gh auth status` passes, and Redis answers on the URL openlanes would use.
- Prints one line per check, ✓ or ✗, and for a ✗ the command that fixes it. It exits non-zero when any check fails.
- `-n` / `--dry-run` prints what it would install and check and changes nothing.
- It is a standalone command (`standalone!`): it needs no project.
- `openlanes init` runs the same checks first and runs setup itself only when one fails, so a new project goes setup → init → start in one go.

## Why it matters

A person should not have to discover the factory's dependencies one failure at a time (M0: a person intervenes as rarely as possible). Today `bin/setup` is the only bootstrap, and it cannot work from an installed gem.

## What already exists

- `bin/setup` bootstraps a checkout of this repo: it installs the Ruby from `.ruby-version` and runs `bundle install`. From an installed gem it is useless (Ruby and the gem's dependencies are already there) and fails (`.ruby-version` and the `Gemfile` are not shipped).
- The gemspec ships `bin/*`, though only `exe/` is on `PATH` (`bindir = "exe"`); `bin/coverage-changed`, `bin/factory-e2e`, `bin/web-e2e` and `bin/plan-number` are contributor tools.
- There is no `Brewfile` in the repo.
- `openlanes init` is in `lib/openlanes/cli/init/`; plan 011 reworks its interview.

## How to tell it's working?

- `openlanes setup` from an empty directory installs nothing on a machine that has everything, and prints ✓ for every check.
- With `gh` logged out, the `gh` check is ✗ with `gh auth login` as the fix, and the exit status is non-zero.
- `openlanes setup -n` changes nothing and lists what it would do.
- The built gem contains `Brewfile` and no longer contains `bin/*`; `bin/setup` keeps working in a checkout.
- `openlanes init` on a machine missing a tool runs setup before its interview; on a ready machine it does not.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

