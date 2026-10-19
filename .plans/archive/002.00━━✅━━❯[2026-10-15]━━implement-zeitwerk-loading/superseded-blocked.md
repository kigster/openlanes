# Blocked: 002.00 implement-zeitwerk-loading

luthen-rael-planner, round 1 (technical). The spec does not fit one pull request, and the split, plus two naming choices, need a decision before a plan can be written.

Measured in the worktree on 2026-10-13 (`rg` over `lib`, `spec`, `exe`):

- 55 files to move under six namespaces, with their specs.
- About 1,300 references to rewrite. No aliases (decided), so every reference moves in the same batch as its constant. `UI` alone has 177 references in 46 files; `Linear` 202 in 30; `Tree` 74 in 35.
- 4 command extractions over 1,055 lines (`create` 336, `run` 367, `unblock` 238, `resync prs` 114).
- 153 Ruby files, 15k lines of code. Nearly every one is touched.

The honest unit count is 12: baseline, six move batches (they all edit the same callers, so they run one after another), four workflow extractions, and the integration check. The cap is eight. Squeezing to eight gives units like "move `Plans`": 17 constants, about 470 references in about 40 files. A reviewer cannot check that in one sitting.

## B1 How to split the spec

Options:

1. **Three plans.**
   - 002.00: boot baseline, eager-load spec, local third-party requires, `Tui` and `Integrations` moves. About 6 units.
   - 002.01: `Plans`, `Runtime`, `Agents` and `Resync` moves, plus the constants Task 2 leaves out (B2). About 6 units.
   - 002.02: Task 3, slimming `Create`, `Run`, `Unblock` and `Resync::Prs` into adapters over workflow objects. About 6 units. Depends on 002.01, because the workflows are written against the new namespaces.
1. **Two plans.** 002.00 covers every move (Tasks 1, 2 and 4) and 002.01 covers the adapters (Task 3). The move plan still has a unit at least as big as `Plans` (about 470 references), so it fails the one-sitting test.
1. **One plan, as specified.** One PR touching about 150 files and 1,300 lines across 12 units. This goes over the size rule.

Recommendation: option 1. Each PR is a mechanical rename that `git diff -M` can review on its own, and the eager-load check after each one catches a missed reference before the next batch builds on it.

## B2 Where the constants Task 2 does not list go

`Dashboard`, `Launcher`, `Config`, `DevWork`, `Reporter`, `StateMachine`, `PullRequest`, `Version`, `Screen::Ratatui`, and the module files `linear.rb` and `resync.rb` have no destination. If the planner assigns them, the "no aliases" rule turns each guess into a rename that has to be undone later.

Proposed (from the domain of each constant's callers):

| Constant | Destination |
| :--- | :--- |
| `StateMachine`, `PullRequest` | `Plans` (with `Status` and `PullRequests`, per `CLAUDE.md`'s single source of truth) |
| `Reporter` | `Plans` (renders the status table from `Tree`) |
| `Dashboard`, `Screen::Ratatui` | `Tui` |
| `Launcher`, `DevWork` | `Runtime` |
| `Config`, `Version` | stay at `Agentilda::` top level |
| `linear.rb` | becomes `integrations/linear.rb`; `linear/mapping.rb` stays ignored by the loader |
| `resync.rb` | stays as `Agentilda::Resync`, with `Adoption` moved inside it |

Recommendation: accept the table, or correct individual rows.

## B3 `Agents` is a class today, and the spec makes it a namespace

`lib/agentilda/agents.rb` defines `class Agents`, the loader for `agents/*.md`. The spec moves `Agent`, `Agents`, `Roster` and `Viewer` *under* `Agentilda::Agents`, so `Agents` has to become a module, and the current class needs a new name.

Options:

1. `Agentilda::Agents::Catalog` holds what `Agents` does today; `Agents::Agent`, `Agents::Roster` and `Agents::Viewer` sit beside it.
1. `Agentilda::Agents::Registry`, with the same layout.
1. Keep `class Agents` and nest the others inside it as `Agents::Agent` and so on. A class used as a namespace works, but Zeitwerk then needs `agents.rb` to define a class and `agents/` to hold its children, so the class and the namespace are tied together.

Recommendation: option 1, `Catalog`. It names what the class holds and leaves `Agents` as a plain namespace like the other five.
