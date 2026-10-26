---
created: 2026-10-24
starts: research
---

# Application Overview and Backlog

Decided with the owner (kig) on 2026-10-24; see `docs/decisions/decisions-on-example-apps.md` (E4 to E7).

## What we are trying to achieve

Two project-level files in `.plans/`. `APPLICATION.md` says what the app does, its goals and its non-goals. `BACKLOG.md` holds detailed candidates that are not plans yet. A grilling step reads `APPLICATION.md` and writes `BACKLOG.md`. `ol create --from-backlog <item>` mints a ⚪ plan from an item and removes it from `BACKLOG.md` (E5). `ol init` writes `docs/application-template.md` to `.plans/APPLICATION.md` when it is missing (E7). researcher, spec-writer and deploy-assessor get `APPLICATION.md` in their prompts (E4), after the dry-rb refactor of the executor.

## Why it matters

Today nothing at project level tells agents what the app is for or what it must not become, so scope creeps one plan at a time. Ideas also have no home between a conversation and a plan folder.

## Task completed when

- `ol create --from-backlog` mints the folder and the item is gone from `BACKLOG.md`.
- A grilling run over an `APPLICATION.md` writes a `BACKLOG.md` of items, each sized to one plan.
- The prompts of researcher, spec-writer and deploy-assessor include `APPLICATION.md` when it exists.
- `ol init` writes `.plans/APPLICATION.md` from the template when absent and never overwrites one.
- `openlanes docs` describes both files, and `docs/STARTING-AN-APP.md` drops its _(planned)_ marks for what landed.

## How to verify

Specs over a `PlansFixture` tree for promotion, for `ol init` writing the template, and for the prompts; one recorded grilling session as an eval case.

## What already exists

- `docs/application-template.md` and `docs/STARTING-AN-APP.md`: the template and the guide (E7).
- `lib/openlanes/cli/init/init.rb`; `lib/openlanes/plans/index.rb` writes `INDEX.md`, the other project-level file.
- `lib/openlanes/cli/create/create.rb` and its `--from` seeding, which `--from-backlog` extends.

## What research needs to settle

- The item format in `BACKLOG.md` that `--from-backlog` addresses (heading slug or numbered list).
- Whether the grilling step is an agent run by the engine or an interactive command.
- How the template reaches `ol init` inside the gem (copied from `docs/` or moved under `lib/`).
