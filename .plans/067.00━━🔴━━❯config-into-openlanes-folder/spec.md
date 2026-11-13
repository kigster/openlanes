---
created: 2026-11-12
starts: planning
depth: medium
frontend: false
depends_on: ["057.00"]
implementation_suggestions:
  - "Change the one constant, `Project::FILE` in `lib/openlanes/support/project.rb`, and let `Config::FILE` follow it, since 54 files read the name from there or spell it out"
  - "`Project.root` finds the root by looking for the file; teach it to look for `.openlanes/config.yml` first and `.openlanes.yml` second"
  - "Move `.openlanes.coverage.yml` to `.openlanes/coverage.yml` in the same change"
implementation_requirements:
  - "A project that still has `.openlanes.yml` keeps working: every command reads it, and prints one line on STDERR naming the new path and the command that moves it"
  - "A project with both files is refused with a message naming both, never silently resolved"
  - "`openlanes init` writes `.openlanes/config.yml` in a new project"
  - "One command moves an existing project across with `git mv`, so the file's history follows it, and previews with `--dry-run`"
  - "Error messages, `--help` text, the README and the bundled skills name the new path"
  - "The entire `.openlanes/` folder is committed with the project and nothing under it is gitignored"
  - "`.openlanes/config.yml` never holds a secret: a `redis_url` carrying a password, or any key whose value looks like a token, is refused when the file is parsed, with a message pointing at the `REDIS_URL` environment variable"
task-completed-when:
  - "This repository's own config is at `.openlanes/config.yml` and `ol start` runs from it"
  - "A temp project with only `.openlanes.yml` runs every command unchanged and sees the one-line notice"
  - "No file under `lib/` spells `.openlanes.yml` outside the legacy read path"
---
# Config Into the .openlanes Folder

Source: the owner, 2026-11-12: "I propose storing that with the repo in the .openlanes folder, and moving the config file into .openlanes/config.yml." "That" is the project memory of plan 066.00.

## What we are trying to achieve

One folder at the project root, `.openlanes/`, tracked in git, holding everything openlanes keeps with a repository: `config.yml` (today `.openlanes.yml`), `coverage.yml` (today `.openlanes.coverage.yml`), and `memory/` when plan 066.00 lands.

## Why it matters

The root already has two dotfiles for one tool and is about to gain a folder. One place is easier to find, to ignore selectively and to explain.

## What already exists

- `Project::FILE = ".openlanes.yml"` in `lib/openlanes/support/project.rb`, which is also how `Project.root` recognises a project. `Config::FILE` is that constant.
- 54 files under `lib/` mention the name, most in comments and messages.
- `Config.current` caches by path and mtime; `Config.write_flag` and `Engine::QualityQuestion` write single keys into the file in place.
- Plan 057.00 (in review) adds a JSON Schema for the config and a writer for the whole file, and makes the control room run from the main checkout. This plan depends on it so the path changes once, after that work merges, and not underneath it.
- `docs/decisions/decisions-on-runtime-state.md` rejected a repo-local `.openlanes/` for runtime state. This folder holds only tracked project files, so that decision stands: nothing in it is ignored and nothing a running process owns lives there.

## Decided

- The new path is `.openlanes/config.yml`.
- The old path keeps working, with a notice, until a person moves it.

## Open, for the planner to settle or ask

- How long the old path is read: one release, or indefinitely.
- Whether the live factory picks up a moved file without a restart.

## How to tell it's working?

- bundle exec rspec
- bundle exec rubocop
- rg -n '\.openlanes\.yml' lib
