# Thin CLI commands over workflow objects

Rewritten by hand on 2026-10-13. The earlier spec (Zeitwerk boot, domain namespaces, command slimming) was written against the `agentilda` code of 2026-09-10. Its first two tasks have since shipped. Only the third is left, and this spec covers that alone. See `decisions.md`.

## Goal

After this ships, `openlanes create`, `openlanes run`, `openlanes unblock` and `openlanes resync prs` are thin adapters. Each command's `call` parses options, calls one workflow object, prints its result and exits. A contributor can test a workflow without constructing a dry-cli command.

## Research

Measured on `main` at `7dc241e` (version 3.0.1), 2026-10-13.

- **Zeitwerk boot: done.** `lib/openlanes.rb` loads everything through Zeitwerk; `support/` and the `cli/<command>/` directories are collapsed.
- **Domain namespaces: done, under different names.** PR #40 (`5e2791d`, 2026-10-06) grouped `lib/` into `plans/`, `lifecycle/`, `agents/`, `adapters/`, `engine/`, `execution/`, `vcs/`, `presentation/`, `support/`, `skills/` and `linear/`, each with a facade module (`Plans.tree`, `Lifecycle.create`, `Engine.runner` and so on). The old spec's `tui/`, `runtime/`, `integrations/` and `resync/` names are void.
- **Command slimming: not done, and the commands have grown.**

| Command | File | Lines then (2026-09) | Lines now |
| :--- | :--- | ---: | ---: |
| `create` | `lib/openlanes/cli/create/create.rb` | 336 | 354 |
| `run` | `lib/openlanes/cli/run/run.rb` | 367 | 576 |
| `unblock` | `lib/openlanes/cli/unblock/unblock.rb` | 238 | 235 |
| `resync prs` | `lib/openlanes/cli/resync/subcommands/prs.rb` | 114 | 111 |

- `dry-monads` is already a dependency and is used in `lifecycle.rb` and `lifecycle/creator.rb`.
- Each command has a spec under `spec/openlanes/cli/` (`create_spec.rb`, `run_spec.rb`, `unblock_spec.rb`, `unblock_edges_spec.rb`, `resync_commands_spec.rb`).

## In Scope

1. **Create.** Seed parsing, pull request fetching, spec drafting, folder settling and next-step calculation move out of `CLI::Create` into a workflow under `Lifecycle`, reached through the `Lifecycle` facade.
1. **Run.** Agent filtering, plan scoping, runtime setup, state-file setup, runner construction and the run summary move out of `CLI::Run` into a workflow under `Engine`, reached through the `Engine` facade.
1. **Unblock.** Target resolution, preflight, outcome reporting, the footer and exit status calculation move out of `CLI::Unblock` into a workflow under `Lifecycle`.
1. **Resync prs.** Change reporting and adoption summaries move out of `CLI::Resync::Prs` into `Lifecycle::Resync` or a presenter under `Presentation`.
1. **Results.** Every extracted workflow returns an explicit result value: `Dry::Monads::Result`, one convention for all four.
1. **Specs.** Every extracted workflow has its own spec that does not construct a dry-cli command. The existing CLI specs keep passing unchanged, apart from constant names.
1. **Green.** `just lint` reports zero offenses and `just test` reports zero failures.

Done when each of the four `call` methods does only option handling, one workflow call, output and exit, and every item above checks out.

## Non-Goals

- Changing any command's flags, output, exit codes or help text.
- Renaming or re-grouping namespaces again; the layout from PR #40 stays.
- Replacing Zeitwerk (decided: Zeitwerk stays).
- Top-level compatibility aliases for anything that moves (decided: none).
- The `--` plan-folder separator (its own plan).
- Slimming commands other than the four above.

## Back End / Front End

A CLI gem; there is no front end in this plan. All units belong to `backend-coder`.
