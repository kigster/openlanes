# Zeitwerk Domain Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Agentilda load cleanly through Zeitwerk while moving business logic toward domain-owned namespaces and leaving CLI classes as thin adapters.

**Architecture:** First verify the Zeitwerk boot with local third-party requires and explicit acronym inflections. Then introduce domain namespace directories without changing behavior, move constants in low-risk batches with no top-level aliases, and finally slim fat command classes into workflow objects.

**Tech Stack:** Ruby 4.0.6, Bundler, Zeitwerk, dry-cli, dry-monads, RSpec.

**Spec:** Conversation design approved on 2026-09-10.

## Global Constraints

- Work only inside `/Users/kig/github/kigster/agentilda`.
- Preserve existing behavior while moving files.
- Use local file-level requires for third-party gems; Zeitwerk only owns Agentilda constants.
- Keep `Agentilda::CLI::*` as command adapters: option parsing, domain call, output, exit.
- Moved constants get no top-level compatibility aliases. Callers move to the new namespaces in the same batch.
  Decided 2026-10-13 by kig: moved constants carry no top-level aliases; the earlier "when practical" wording is superseded.
- Zeitwerk is the loader. Explicit require is not adopted; the loader recommendation in `docs/REFACTOR.md` is superseded.
  Decided 2026-10-13 by kig: keep Zeitwerk as the loader; `docs/REFACTOR.md` loader guidance does not apply.
- Domain directories follow the namespaces in Task 2 (`tui/`, `plans/`, `runtime/`, `integrations/`, `agents/`, `resync/`). This overrides `docs/REFACTOR.md` R1.
  Decided 2026-10-13 by kig: the domain layout in Task 2 is the approved scheme.
- The `--` plan-folder separator is out of scope. It gets its own plan and changes nothing here.
  Decided 2026-10-13 by kig: `--` separator is excluded from this plan.
- Do not start the TUI redesign until loader and base functionality are green.

---

### Task 1: Verify Zeitwerk Boot

Zeitwerk is already wired and green, so this task verifies and baselines the existing boot rather than repairing it.

**Files:**
- Modify: `lib/agentilda.rb`
- Modify: `lib/agentilda/linear.rb`
- Modify: files that directly reference third-party constants
- Test: `spec/agentilda/load_spec.rb`

**Interfaces:**
- Produces: `require "agentilda"` succeeds without eager-loading every domain file manually.
- Produces: `bundle exec tilda` reaches CLI help behavior.

- [ ] **Step 1: Write the failing load test**

```ruby
# spec/agentilda/load_spec.rb
require "open3"

RSpec.describe "agentilda load path" do
  it "loads the gem entrypoint without eager-load NameError failures" do
    output, status = Open3.capture2e(
      RbConfig.ruby,
      "-Ilib",
      "-e",
      "require 'agentilda'; puts 'loaded'"
    )

    expect([status.success?, output]).to eq([true, "loaded\n"])
  end
end
```

- [ ] **Step 2: Run the executable to capture the current failure**

Run: `eval "$(rbenv init -)" && bundle exec tilda`

Expected before the fix: a `NameError` or `Zeitwerk::NameError`.

- [ ] **Step 3: Move third-party requires to owning files**

Add direct requires such as `dry/monads`, `tty/command`, `unicode/display_width`, `fileutils`, `shellwords`, and `parallel` to the files that use those constants.

- [ ] **Step 4: Fix acronym inflections**

Configure Zeitwerk inflections in `lib/agentilda.rb` for constants Ruby code already exposes:

```ruby
loader.inflector.inflect(
  "api" => "API",
  "cli" => "CLI",
  "github" => "GitHub",
  "ui" => "UI"
)
```

- [ ] **Step 5: Remove manual require loops**

Delete the component loop in `lib/agentilda.rb` and the part loop in `lib/agentilda/linear.rb` once all constants autoload correctly.

- [ ] **Step 6: Verify**

Run: `eval "$(rbenv init -)" && bundle exec ruby -Ilib -e 'require "agentilda"; puts "loaded"'`

Run: `eval "$(rbenv init -)" && bundle exec tilda`

Expected: both commands succeed.

### Task 2: Introduce Domain Namespaces Without Behavioral Changes

**Files:**
- Modify/create: `lib/agentilda/tui/**`
- Modify/create: `lib/agentilda/plans/**`
- Modify/create: `lib/agentilda/runtime/**`
- Modify/create: `lib/agentilda/integrations/**`
- Modify/create: `lib/agentilda/agents/**`
- Modify/create: `lib/agentilda/resync/**`

**Interfaces:**
- Produces: domain constants under their new namespace.
- Replaces: existing top-level constants move to their domain namespace. No top-level aliases are kept.

- [ ] **Step 1: Move low-risk UI files**

Move display-only classes and modules first: `UI`, `Screen`, `Console`, `Board`, `Keyboard`, `Clock`, `ProgressLog`, and `Tally`.

- [ ] **Step 2: Move integration wrappers**

Move `GitHub` to `Agentilda::Integrations::GitHub` and Linear files to `Agentilda::Integrations::Linear`, updating every caller in the same batch.

- [ ] **Step 3: Move plan model and document files**

Move `Tree`, `Feature`, `Subject`, `Ordinal`, `Status`, `StateFile`, `Frontmatter`, `Markdown`, `Ledger`, `PullRequests`, `Creator`, `Brief`, `Documentation`, `Diagram`, and `Index`.

- [ ] **Step 4: Move runtime orchestration**

Move `Runner`, `Dispatcher`, `Executor`, `Child`, `Transcript`, `Control`, `Mailbox`, `Unblocker`, `Worktree`, and `Publisher`.

- [ ] **Step 5: Move agent roster files**

Move `Agent`, `Agents`, `Roster`, and `Viewer` under `Agentilda::Agents`.

- [ ] **Step 6: Move resync domain**

Move `Resync::Dirs`, `Resync::Prs`, and `Adoption` under a coherent resync namespace.

- [ ] **Step 7: Verify after each batch**

Run the focused specs for files moved in the batch, then run `bundle exec tilda`.

### Task 3: Slim Command Classes Into Adapters

**Files:**
- Modify: `lib/agentilda/cli/create/create.rb`
- Modify: `lib/agentilda/cli/run/run.rb`
- Modify: `lib/agentilda/cli/unblock/unblock.rb`
- Modify: `lib/agentilda/cli/resync/subcommands/prs.rb`
- Create: workflow objects in the relevant domain namespace

**Interfaces:**
- Produces: command classes that parse options, call a workflow, print results, and exit.
- Produces: workflow objects returning explicit result values, preferably `Dry::Monads::Result`.

- [ ] **Step 1: Extract create workflow**

Move seed parsing, PR fetching, spec drafting, folder settling, and next-step calculation out of `CLI::Create`.

- [ ] **Step 2: Extract run workflow**

Move agent filtering, plan scoping, runtime setup, state-file setup, runner construction, and run summary generation out of `CLI::Run`.

- [ ] **Step 3: Extract unblock workflow**

Move target resolution reporting, preflight rendering, outcome reporting, footer rendering, and exit status calculation out of `CLI::Unblock`.

- [ ] **Step 4: Extract resync PR presentation**

Move change reporting and adoption summaries out of `CLI::Resync::Prs`.

- [ ] **Step 5: Verify**

Run all CLI specs and the executable smoke test.

### Task 4: Full Verification

**Files:**
- Modify only if verification exposes behavior-preserving fixes.

**Interfaces:**
- Produces: green RSpec suite or a clearly documented external blocker.
- Produces: `bundle exec tilda` works.

- [ ] **Step 1: Run loader verification**

Run: `eval "$(rbenv init -)" && bundle exec ruby -Ilib -e 'require "agentilda"; Zeitwerk::Loader.eager_load_all; puts "eager loaded"'`

- [ ] **Step 2: Run CLI smoke**

Run: `eval "$(rbenv init -)" && bundle exec tilda`

- [ ] **Step 3: Run tests**

Run: `eval "$(rbenv init -)" && bundle exec rspec`

- [ ] **Step 4: Document remaining work**

If the TUI redesign is still pending, leave it out of this refactor and capture it as the next task.

---

## Research

### Current State of Zeitwerk in Agentilda

**Finding**: Zeitwerk is already implemented and fully operational. The code loads cleanly without errors, the CLI runs correctly, and all tests pass.

**Evidence:**
- `lib/agentilda.rb:11-37` (current state): Zeitwerk loader is instantiated, inflections configured, collapse/ignore directives in place, and `loader.setup` called.
- Test results: `bundle exec rspec` shows 1090 examples, 0 failures, 97.28% coverage (as of 2026-09-17).
- Load verification: `ruby -Ilib -e 'require "agentilda"; puts "loaded successfully"'` succeeds without errors.
- CLI smoke test: `bundle exec tilda --help` displays help correctly.

**Implication**: Task 1 in the spec ("Stabilize Zeitwerk Boot") describes work that is already complete. The actual refactoring work is Tasks 2-4 (moving files to domain namespaces and slimming CLI classes).

### Conflict Between Specification and REFACTOR.md

**Finding**: The specification assumes Zeitwerk needs to be stabilized, but the comprehensive refactoring document at `docs/REFACTOR.md` explicitly recommends **against** using Zeitwerk.

**Evidence from REFACTOR.md (lines 84-89)**:
> "For agentilda, **explicit require is recommended** because:
> - Current codebase already uses this pattern
> - Load order matters (domain before operations before execution)
> - SimpleCov integration depends on predictable loading
> - Easier to debug than autoloading"

**The Contradiction**:
1. Gemspec line 58: `spec.add_dependency "zeitwerk"` — Zeitwerk is a hard dependency
2. `lib/agentilda.rb:11-37`: Zeitwerk is already wired up and working
3. REFACTOR.md lines 76-89: Explicit require is the recommended approach, Zeitwerk is not recommended

**Current Reality**: Zeitwerk is present, used, and functional. The codebase achieves its goal (clean loading, correct behavior) through Zeitwerk today.

### Unresolved Design Decision: File Organization Scheme

**Finding**: REFACTOR.md identifies an unresolved contradiction (Risk R1, lines 356) between two proposed directory structures, but no decision has been recorded.

**The Two Schemes**:

1. **Command-centric grouping** (from REFACTOR.md introduction, lines 4-5):
   - Move helper classes next to their command
   - Example: `creator.rb` → `lib/agentilda/cli/create/creator.rb`
   - Shared helpers go to `lib/agentilda/shared/`

2. **Layer-based grouping** (from REFACTOR.md research section, lines 91-136):
   - Organize by architectural layer: models, queries, commands, execution, reporting, etc.
   - Example: `creator.rb` → `lib/agentilda/commands/creator.rb`
   - 8 module groups with clear dependency tiers

**What the Spec Assumes**: The spec uses layer-based language (lines 94-99 reference `lib/agentilda/tui/`, `lib/agentilda/plans/`, `lib/agentilda/runtime/`, etc.), which suggests the layer-based approach, but this has not been explicitly chosen.

**Why This Matters**: Choosing the wrong scheme means all file moves must be redone. REFACTOR.md (Risk R1 mitigation) explicitly requires settling this in "Phase 0" before any files are moved.

### Grouping Scheme Analysis

**Layer-based approach (favored by spec)**:
- **Pros**: Clean separation of concerns, industry-standard pattern (matches Devise, Sidekiq), natural dependency flow
- **Cons**: Deeper nesting (Agentilda::Tui::UI vs. Agentilda::UI), requires new module entry points
- **Dependency order**: ui → models → queries → commands → execution → reporting
- **Files affected**: All 40+ files under `lib/agentilda/`

**Command-centric approach (from introduction)**:
- **Pros**: Keeps commands and their tools colocated, mirrors existing cli/ structure
- **Cons**: Leaves shared classes unclear (shared/ vs. models/ vs. queries/), harder to navigate for non-CLI code
- **Structure**: cli/{create,run,unblock}/command.rb paired with helper files
- **Files affected**: CLI files primarily; other files need a secondary home

### Recommendation to Planning Phase

The specification assumes layer-based grouping but does not explicitly declare it. Before implementing Task 2, confirm that layer-based is the chosen scheme, or revise the spec's directory structure references to match the actual design decision.

### Corrections to Task 1

Task 1 ("Stabilize Zeitwerk Boot") is descriptively accurate as written (steps 1-6 are sound practices), but its problem statement is moot: the boot is already stable. Consider relabeling Task 1 as "Verify Zeitwerk Configuration" and making it:
- A verification step that confirms inflections, collapse, and ignore directives are complete
- A baseline capture of test results for comparison during later refactoring
- Confirmation that eager-loading works (Task 4, Step 1 already requires this)

### Open Questions for Yoda-Writer

1. **Is Zeitwerk the intended loader**, or should the specification be updated to reflect REFACTOR.md's recommendation for explicit require? (Currently both are true, which is inconsistent.)
2. **Which grouping scheme has been chosen** — layer-based (models, queries, commands, execution, reporting, etc.) or command-centric (cli/{cmd}/command.rb + shared/)?
3. **Should constant names change** during reorganization, or should compatibility aliases preserve the flat `Agentilda::*` namespace?
4. **When should the `--` separator for plan folder names** be introduced — as part of this work (Phase 1 in REFACTOR.md) or deferred to a separate plan?

### Findings, Conclusion & References

**Key Findings:**
- Zeitwerk is already a working dependency, not a blocker
- All baseline tests pass; code loads cleanly
- REFACTOR.md provides comprehensive analysis and recommends explicit require instead of Zeitwerk
- Two incompatible file organization schemes are proposed without a decided preference
- The specification aligns with the layer-based approach but does not explicitly declare this choice

**Conclusion:** The specification is ready to implement but should clarify (1) the file organization scheme choice, (2) whether Zeitwerk or explicit require is authoritative when they conflict, and (3) whether constant namespace flattening is acceptable. All three have been researched in REFACTOR.md but remain unresolved product decisions.

**References:**
- Current state verification: `lib/agentilda.rb` lines 11-37; `bundle exec rspec` output (2026-09-17); test coverage badge
- REFACTOR.md: Lines 84-89 (loader recommendation), 91-136 (proposed layer-based structure), 356-357 (Risk R1 unresolved choice)
- Architecture documentation: `CLAUDE.md` Layout section (current flat structure authority)
- Gemspec: Line 58 confirms Zeitwerk as runtime dependency






---

## Problem Framing

Two framings of the same work:

1. **Loader repair.** "Agentilda does not load cleanly under Zeitwerk; fix the boot." Research shows this is false: the loader is wired and green (`lib/agentilda.rb:12-38`, `spec/agentilda/load_spec.rb` exists, 1090 examples / 0 failures per `## Research`).
1. **Namespace reorganization.** "The flat `Agentilda::*` namespace hides domain boundaries and the CLI classes carry business logic (`cli/create/create.rb` 336 lines, `cli/run/run.rb` 367, `cli/unblock/unblock.rb` 238, `cli/resync/subcommands/prs.rb` 114)." The work is moving constants into domain namespaces and thinning commands.

**Chosen: framing 2.** Framing 1 is already done, so Task 1 shrinks to a baseline check, and all of the remaining value is in Tasks 2 to 4.

## Goal

After this ships, every business-logic constant lives under a domain namespace (`Tui`, `Plans`, `Runtime`, `Integrations`, `Agents`, `Resync`) that Zeitwerk autoloads from a matching directory, and the `CLI::*` command classes only parse options, call one workflow object, print its result and exit. A contributor can find a class by its domain and test a workflow without constructing a dry-cli command.

## Non-Goals

- Changing user-visible behavior, flags, output or exit codes of any command.
- Replacing Zeitwerk with explicit requires (decided: Zeitwerk stays).
- Keeping top-level compatibility aliases for moved constants (decided: none).
- Introducing the `--` plan-folder separator (own plan).
- The TUI redesign; it starts only after loader and base functionality are green.
- Renaming the gem, executables or `.plans` folder format.
- Raising or restructuring test coverage beyond keeping the current level (97.28%).

## In Scope

Each item is checkable by the command shown.

1. **Boot baseline.** `bundle exec ruby -Ilib -e 'require "agentilda"; puts "loaded"'` prints `loaded`; `spec/agentilda/load_spec.rb` passes; the suite baseline (example and failure count) is recorded in the PR.
1. **Inflections and ignores audited.** `lib/agentilda.rb` inflection, collapse and ignore lists cover every moved directory; `Zeitwerk::Loader.eager_load_all` succeeds (Task 4 Step 1 command).
1. **Third-party requires local.** Each file that uses `Dry::Monads`, `TTY::Command`, `Unicode::DisplayWidth` or `Parallel` requires it itself: `rg -n "^require" lib` shows the require in the owning file.
1. **UI batch moved.** `UI`, `Screen`, `Console`, `Board`, `Keyboard`, `Clock`, `ProgressLog`, `Tally` resolve only as `Agentilda::Tui::*`; `Agentilda::UI` raises `NameError`.
1. **Integrations moved.** `GitHub` and `Linear::*` resolve only under `Agentilda::Integrations`; the `GitHub`/`Linear::API` seam doubles in specs still inject.
1. **Plan model moved.** `Tree`, `Feature`, `Subject`, `Ordinal`, `Status`, `StateFile`, `Frontmatter`, `Markdown`, `Ledger`, `PullRequests`, `Creator`, `Brief`, `Documentation`, `Diagram`, `Index` resolve only under `Agentilda::Plans`.
1. **Runtime moved.** `Runner`, `Dispatcher`, `Executor`, `Child`, `Transcript`, `Control`, `Mailbox`, `Unblocker`, `Worktree`, `Publisher` resolve only under `Agentilda::Runtime`.
1. **Agents moved.** `Agent`, `Agents`, `Roster`, `Viewer` resolve only under `Agentilda::Agents`.
1. **Resync moved.** `Resync::Dirs`, `Resync::Prs`, `Adoption` live under one `Agentilda::Resync` namespace.
1. **No stragglers.** `rg` for each old top-level constant name in `lib`, `spec`, `exe`, `agents/*.md` and docs finds no reference to the old path.
1. **Create/Run/Unblock/Resync-Prs adapters thin.** Each named command's `call` does only option handling, one workflow invocation, output and exit; the extracted workflow has its own spec and returns an explicit result value.
1. **Derived docs still derive.** `agentilda docs` and `agentilda states` run and produce no diff apart from namespace-driven changes, since `CLAUDE.md` says they derive from `STATUSES` and the `aasm` block.
1. **Green at the end.** `bundle exec rspec` shows no failures beyond the documented baseline; `bundle exec tilda --help` exits 0.

## Out of Scope

- `--` separator: separate plan, already decided.
- TUI redesign: depends on this plan's output.
- Linting config (`.standard.yml`, `just lint` fix): `CLAUDE.md` calls it a separate fix.
- Missing monorepo orphans (`bin/install`, `bin/setup-worktree`, schema files): the known baseline red specs are not caused by this work.
- Rewriting `docs/REFACTOR.md`: its loader and layout guidance is marked superseded here; editing it is documentation cleanup, not part of the move.

## Back End / Front End

This is a CLI gem with no web front end. The pair maps to library versus terminal surface.

| Item | `luke-backend` | `rey-frontend` |
| :--- | :--- | :--- |
| Boot baseline, inflections, requires | all | none |
| Plans, Runtime, Integrations, Agents, Resync moves | all | none |
| Tui move (`UI`, `Screen`, `Console`, `Board`, ...) | caller updates | owns the namespace and its rendering specs |
| Create/Run/Unblock/Resync-Prs workflows | workflow objects and result values | adapters: output, exit, help text |
| Docs/states regeneration | none | verifies output unchanged |

## Open Questions

Resolved by the Global Constraints (decided 2026-10-13 by kig), so none of leah's four remain open: Zeitwerk is the loader; the Task 2 layout is the scheme; no aliases; `--` is excluded.

Left unanswered by the spec, all assumptions:

1. **Constants not listed in Task 2.** `Dashboard`, `Launcher`, `Config`, `DevWork`, `Reporter`, `StateMachine`, `PullRequest`, `Resync` (the module file `lib/agentilda/resync.rb`), `Linear` module file, `Version`, `Screen::Ratatui` have no destination. Proposed: planner assigns them using the domain of their callers, and records each in the PR. Not resolved here.
1. **`PullRequest` versus `PullRequests`.** Only the plural is listed; assumed both go to `Plans`.
1. **`StateMachine` and `Status`.** `CLAUDE.md` treats them as one source of truth; assumed to move together into `Plans`.
1. **`agents/*.md` frontmatter and `Agents` routing** read class or file names? Not checked; the planner should confirm no markdown references a moved constant path.
1. **`linear/mapping.rb`** is ignored by the loader (`lib/agentilda.rb:37`). Whether it stays ignored after the move is unverified.
1. **Spec directory layout.** Whether `spec/agentilda/**` mirrors the new namespaces is unspecified; assumed yes for moved files.
1. **Suite baseline.** `CLAUDE.md` states 648 examples / 121 failures; the research cites 1090 / 0 on 2026-09-17. They disagree; Task 1 must capture the real number first.

## Risks to Planning or Execution

- **Big-bang rename without aliases.** Any missed reference is a `NameError` at runtime in a rarely exercised path. Mitigation: one batch per domain, eager-load check after each.
- **Baseline ambiguity** (see open question 7): a regression can hide in the "known red" set.
- **`collapse` and `ignore` paths** in `lib/agentilda.rb:22-37` are literal strings; a moved directory silently falls out of collapse and changes constant names.
- **Order dependence.** Tui first, then Integrations, Plans, Runtime, Agents, Resync follows dependency direction; moving `Plans` before `Runtime` callers are updated stalls the batch.
- **Concurrent agents** editing `lib/agentilda/**` while files move; use a worktree, as the folder already does.
- **Result type scope creep.** "Preferably `Dry::Monads::Result`" in Task 3 may be argued per workflow; keep one convention.

## Conclusion

When this ships, `Agentilda` is organized into six domain namespaces under `lib/agentilda/`, with no top-level aliases, loaded by Zeitwerk with an eager-load check in the suite. `Create`, `Run`, `Unblock` and `Resync::Prs` commands are thin adapters over workflow objects that have their own specs. Behavior, flags and generated docs are unchanged, and the suite is no worse than its recorded baseline.
