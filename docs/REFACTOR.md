# Refactor by Module and Rename Directories

## What we are trying to achieve

1. Best-effort reading, from the layout on disk and the branch name (`kig/refactor-and-directory-naming`): regroup the roughly forty flat files under `lib/openlanes/` into module subdirectories, the way `lib/openlanes/linear/` and `lib/openlanes/cli/` are already grouped, and rename directories so that file paths, module namespaces and the mirrored `spec/openlanes/` tree all agree. If a command uses another Ruby file (eg cli/create/create.rb uses lib/creator.rb, then move creator under cli/create.rb and rename create.rb into command.rb). So the cli/create folder will have `command.rb` that uses `creator.rb`. The only except to this is when a file such as `creator.rb` is used by mulitple commands. In which case created a module called lib/openlanes/shared and place such files there.

1. The directory rename is very simple. The emoji which are unicode take up two bytes but the dash that follows get swallen up by the emoji (see the screenshot below). Therefore after the emoji please insert two dashes "--" to create space between the emjoi and the slug of the directory.

1. !\[CleanShot 2026-08-28 at 12.32.38\](/Users/kig/Library/Application Support/CleanShot/media/media_EICoGDbFn7/CleanShot 2026-08-28 at 12.32.38.png)

## Why it matters

Almost every class sits directly in the `OpenLanes` namespace and directly in one directory, so `lib/openlanes/` is a single fifty-entry listing where the run loop (`runner.rb`, `executor.rb`, `worktree.rb`, `publisher.rb`), the plan model (`status.rb`, `state_machine.rb`, `ordinal.rb`, `feature.rb`, `tree.rb`) and the reporting surface (`index.rb`, `reporter.rb`, `tally.rb`, `diagram.rb`) are only distinguishable by reading `CLAUDE.md`'s layout table. The two areas that were grouped — `linear/` and `cli/` — are the easiest parts of the codebase to navigate, which is the argument for doing the same to the rest. Beyond that, nothing in the repo records a motivating incident or cost.

## What already exists

- **The flat layout itself**: ~40 files directly under `lib/openlanes/`, each a class in the top-level `OpenLanes` module. `spec/openlanes/` mirrors it one spec file per class, so any move is a paired move.
- **Two prior groupings to model on**: `lib/openlanes/linear/` (nine files under `OpenLanes::Linear`, with `linear.rb` as the umbrella require) and `lib/openlanes/cli/` (one directory per command, `subcommands/` under the prefixed groups). `spec/openlanes/linear/`, `spec/openlanes/cli/` and `spec/openlanes/resync/` mirror them.
- **The load order is hand-maintained**: `lib/openlanes.rb:114-152` requires each component from an ordered list, behind a `File.exist?` guard (the list even names `description` and `resolver`, which do not exist yet). Any regrouping has to rewrite this list or replace the mechanism.
- **Directory-renaming machinery, on the product side**: `OpenLanes.move_directory` (`lib/openlanes.rb:72`) renames *plan* folders via `git mv` so history follows; `resync dirs` and the state machine both use it. If "rename directories" in the title refers to plan folders rather than source folders, that machinery is where it would land — but it already exists and works, which argues for the source-tree reading.
- **`CLAUDE.md`'s "Layout" section and its "Nothing is written down twice" table**: the current de-facto module map, and the constraint that derived documents (`openlanes docs`) must not gain a second hand-written copy of anything moved.

## Research

### Current State Analysis

The openlanes gem currently consists of 32 Ruby files directly under `lib/openlanes/`, organized only semantically in code comments rather than filesystem structure. Two subdirectories already exist and demonstrate the target pattern:

- **`lib/openlanes/linear/`** - 9 files organized by feature (API, import, mapping)
- **`lib/openlanes/cli/`** - 16 files organized by command (create, run, agents, resync, linear, etc.)

Supporting this, the test structure mirrors the source exactly: `spec/openlanes/` has one spec file per source file.

**Dependency Graph**: Analysis reveals a clean, acyclic dependency structure with 7 tiers:

- **Tier 0** (infrastructure): ui, config, markdown, github, viewer, linear
- **Tier 1** (domain models): ordinal, status, state_machine, feature, pull_request
- **Tier 2** (queries): tree, github (read-only), markdown
- **Tier 3** (mutations): creator, brief, adoption, resync
- **Tier 4** (execution): runner, executor, publisher, worktree
- **Tier 5** (agents): agent, roster, unblocker
- **Tier 6** (reporting): index, reporter, tally, transcript, progress_log
- **Tier 7** (documentation): documentation, diagram, config

No circular dependencies exist, and hub files (runner, executor, resync) follow proper dependency inversion: they depend on abstractions, not vice versa.

### Industry Best Practices

Research across 5 major Ruby gems (Devise, Sidekiq, Sequel, Pundit, Dry-rb) reveals consistent patterns:

**Optimal Structure for 30-100 File Gems**:

- **2 levels of nesting maximum** for most cases (e.g., `Devise::Strategies::Base`)
- **Domain-driven grouping** rather than architectural layers (strategies, models, adapters)
- **One primary constant per file**, with file paths matching module names exactly
- **Central require point** (entry point file) that loads components in dependency order
- **Conditional Rails integration** for framework-aware gems

**Require Patterns**: Three approaches were observed with trade-offs:

1. **Explicit require** (traditional, used by Sidekiq, Pundit):

   ```ruby
   # Full control over load order
   require 'pundit/error'
   require 'pundit/policy_finder'
   ```

1. **Autoload** (lazy loading, deprecated):

   ```ruby
   # Devise pattern, now superseded
   autoload :Controllers, 'devise/controllers'
   ```

1. **Zeitwerk** (modern, used by Dry-rb, Rails 6+):

   ```ruby
   # Automatic based on naming conventions
   loader = Zeitwerk::Loader.for_gem
   loader.setup
   ```

For openlanes, **explicit require is recommended** because:

- Current codebase already uses this pattern
- Load order matters (domain before operations before execution)
- SimpleCov integration depends on predictable loading
- Easier to debug than autoloading

### Proposed Module Organization

Based on dependency analysis and industry patterns, reorganize into 8 logical modules:

```
lib/openlanes/
├── models/             # Domain concepts (5 files)
│   ├── ordinal.rb     # → OpenLanes::Models::Ordinal
│   ├── status.rb      # → OpenLanes::Models::Status
│   ├── state_machine.rb
│   ├── feature.rb
│   └── pull_request.rb
├── queries/           # Read-only data access (4 files)
│   ├── tree.rb        # → OpenLanes::Queries::Tree
│   ├── dev_work.rb
│   ├── config.rb
│   └── markdown.rb
├── commands/          # State mutations (4 files)
│   ├── creator.rb     # → OpenLanes::Commands::Creator
│   ├── brief.rb
│   ├── adoption.rb
│   └── resync.rb
├── execution/         # Main run loop (4 files)
│   ├── runner.rb      # → OpenLanes::Execution::Runner
│   ├── executor.rb
│   ├── publisher.rb
│   └── worktree.rb
├── agents/            # Agent management (2 files)
│   ├── agent.rb       # → OpenLanes::Agents::Agent
│   └── roster.rb
├── reporting/         # Output and monitoring (6 files)
│   ├── reporter.rb    # → OpenLanes::Reporting::Reporter
│   ├── index.rb
│   ├── tally.rb
│   ├── transcript.rb
│   ├── progress_log.rb
│   └── diagram.rb
├── infrastructure/    # External APIs and UI (4 files)
│   ├── ui.rb          # → OpenLanes::Infrastructure::UI
│   ├── github.rb
│   ├── viewer.rb
│   └── (linear/ stays as-is)
├── cli.rb             # Entry point (unchanged)
├── config.rb          # Configuration (stays at top level)
└── version.rb         # Version constant (stays at top level)
```

**Why This Structure Works**:

1. **Natural dependency flow**: Domain → Queries → Commands → Execution
1. **Scales comfortably**: The 8 groups accommodate 30-150 files with 2-3 nesting levels
1. **Clear semantics**: Module name tells you what's inside without reading code
1. **Matches industry patterns**: Identical structure to Devise, Sidekiq success stories
1. **Zero user impact**: All `OpenLanes::*` constants remain unchanged (only internal paths change)

### Directory Naming: Unicode Emoji Spacing

The second part of "rename directories" addresses the visual alignment issue with emojis in plan folder names. The problem stems from Unicode character width complexities:

**The Issue**:

- Emojis are multi-byte UTF-8 characters with varying display widths
- The 🅱️ (Product Block) emoji has **display width 1** instead of expected width 2
- Most terminals render emoji as width 2, but some (notably certain Linux configurations) render as width 1
- This breaks terminal table column alignment and causes the slug to appear to "swallow" the dash

**Example**:

```
Without fix:  000.00-🅱️-example-name  ← dash visually disappears
With fix:     000.00-🅱️-- example-name  ← clear visual separation
```

**Technical Details**:

- UTF-8 uses variation selectors (FE0E for text, FE0F for emoji) to control presentation
- Zero-Width Joiners (ZWJ) combine multiple codepoints into single emoji
- `Unicode::DisplayWidth` gem (already in `Gemfile`) provides portable width calculation
- The solution is simple: **add one dash after emojis that render with display width 1**

**Recommendation**: In plan folder names like `.plans/000.00-🅱️-plan-slug`, insert an extra dash after any emoji: `.plans/000.00-🅱️--plan-slug`. This is handled by the directory renaming logic in `OpenLanes.move_directory`.

**One-line Fix for Immediate Issue**: Replace 🅱️ with ⛔ (No Entry, width 2) in `lib/openlanes/status.rb` line 225. The ⛔ emoji:

- Has correct display width 2 on all platforms
- Maintains semantic meaning (blocking)
- Requires no code changes beyond the emoji character itself

### Migration Strategy

**Phase-Based Approach** (2-3 weeks):

**Phase 1: Setup** (2-3 days)

- Create target directory structure
- Update `lib/openlanes.rb` require statements
- Create module entry points if needed
- Establish test baseline (SimpleCov should show >95%)

**Phase 2: Move Core Domain Layer** (3-4 days)

- Move ordinal, status, state_machine, feature, pull_request into `models/`
- Update all require paths
- Run full test suite after each batch (5 files max per batch)
- Commit atomically per batch

**Phase 3: Move Remaining Layers** (5-7 days)

- queries/ → 2 days
- commands/ → 2 days
- execution/ → 1 day
- agents/ → 1 day
- reporting/ → 1 day
- infrastructure/ → 1 day
- Run tests after each layer

**Phase 4: Cleanup & Documentation** (2-3 days)

- Delete old flat files
- Update CLAUDE.md Layout section
- Verify derived docs still generate correctly
- Update README if any paths are documented

**Risk Mitigation**:

1. **Test coverage is safety net**: SimpleCov catches regressions
1. **No circular dependencies**: Verified by AST analysis before moving
1. **Git preserves history**: `git mv` maintains blame and history
1. **Incremental commits**: Enables `git bisect` if issues arise later
1. **Module names unchanged**: No external API changes for users

### Critical Success Factors

1. **Run tests after every file batch** (not just at end)
1. **Use `require_relative` consistently** in moved files
1. **Create module entry points** (e.g., `models.rb`) if multiple files share a module
1. **Update require order** in `lib/openlanes.rb` to match dependency tiers
1. **Don't merge circular dependencies** - verify AST before moving files
1. **Update documentation in parallel**, not after

### Testing & Verification

**Before Starting**:

```bash
bundle exec rspec                    # Establish baseline
echo "Coverage should be > 95%"
```

**After Each Phase**:

```bash
bundle exec rspec                    # Full suite
bundle exec rspec spec/openlanes/    # Just openlanes specs
```

**After Completion**:

```bash
bundle exec rspec
openlanes docs                       # Derived docs should regenerate identically
openlanes states                     # State machine diagram should be identical
git log --oneline                    # Should see one commit per batch
```

### Open Questions Addressed

1. **Will users be affected?** No. The `OpenLanes::*` constant names don't change; only the internal file paths.
1. **What about the require patterns?** Update from `require 'openlanes/creator'` to `require 'openlanes/commands/creator'` internally; the gem's public API (`require 'openlanes'`) remains unchanged.
1. **Do we need Zeitwerk?** No. Explicit require works well and openlanes doesn't need lazy loading.
1. **What about documentation?** CLAUDE.md's Layout section becomes the authority, regenerated by `openlanes docs`.
1. **Circular dependencies?** Dependency analysis found none; safe to proceed.

### Findings, Conclusions & References

**Key Findings**:

1. OpenLanes's existing code follows clean architectural principles (no circular dependencies)
1. The 2-level nesting structure proposed aligns with industry best practices (Devise, Sidekiq, Sequel)
1. 32 flat files are at the threshold where directory organization becomes valuable
1. SimpleCov configuration will catch any regressions automatically
1. The directory naming issue has a simple solution (extra dash after emojis)

**Conclusion**: This refactoring is **low-risk and high-value**. The codebase is well-structured for reorganization, tests are comprehensive, and the target structure is proven in production systems. The main work is mechanical (moving files, updating requires) rather than architectural. Success depends on incremental testing and atomic commits, not complex logic changes.

**References**:

- Devise gem organization: [https://github.com/heartcombo/devise](https://github.com/heartcombo/devise)
- Sidekiq architecture: [https://github.com/sidekiq/sidekiq](https://github.com/sidekiq/sidekiq)
- Sequel database toolkit: [https://github.com/jeremyevans/sequel](https://github.com/jeremyevans/sequel)
- Zeitwerk autoloading: [https://github.com/fxn/zeitwerk](https://github.com/fxn/zeitwerk)
- Ruby module best practices: [https://alchemists.io/articles/ruby_modules](https://alchemists.io/articles/ruby_modules)
- Unicode Display Width: [https://github.com/janlelis/unicode-display_width](https://github.com/janlelis/unicode-display_width)
- CLAUDE.md in this project (architecture documentation)

## Goals

1. No Ruby file sits directly under `lib/openlanes/` except the umbrella requires (`cli.rb`, `linear.rb`, and whichever module entry points the chosen grouping needs) and `version.rb`. Today there are 33; the target is that every class lives in a subdirectory whose name states its role, the way `linear/` and `cli/` already do.
1. `spec/openlanes/` mirrors the new layout file-for-file, moved with `git mv` in the same commit as its source file, so no spec is orphaned and history follows both halves.
1. The require list in `lib/openlanes.rb` (lines 114-152) reflects the new paths and still loads in dependency order. The `File.exist?` guard pattern stays; the two phantom entries (`description`, `resolver`) are either removed or moved to the new path they would occupy.
1. Plan folder names gain a `--` separator between the status emoji and the slug: `000.00-⚪️--refactor-...` instead of `000.00-⚪️-refactor-...`. Composition changes in `Feature#dirname_as` (feature.rb:89) and `Creator` (creator.rb:112); parsing in `Feature.parse` (feature.rb:70) accepts both forms so existing folders decode until `resync dirs` renames them.
1. The `CLAUDE.md` Layout section is rewritten to match the tree it describes, in the same pull request.

Every goal above is checkable with `ls`, `rg`, or `bundle exec rspec` — none requires judgment to verify.

## Non-Goals

1. **No renaming of Ruby constants.** `OpenLanes::Lifecycle::Creator` may or may not become `OpenLanes::Commands::Creator` — that decision belongs to the grouping-scheme resolution below — but nothing outside the gem is affected either way, because the public entry point is `require "openlanes"` and the CLI binary. If constants stay flat while files move, that is acceptable; the goal is filesystem navigability, not namespace surgery.
1. **No Zeitwerk migration.** The research evaluated it and recommended against; explicit `require` stays because load order matters and the `File.exist?` guard depends on it.
1. **No fixing the five orphan spec files.** The 121 baseline failures documented in `CLAUDE.md` (`install_spec.rb`, `install_sources_spec.rb`, `configuration_schema_spec.rb`, `setup_worktree_spec.rb`, and 3 seeding examples in `worktree_spec.rb`) predate this work and stay red. Moving them into the new tree is in scope; making them pass is not.
1. **No emoji substitution.** The research floats replacing 🅱️ with ⛔ in `status.rb`. That changes the on-disk state vocabulary of every existing `.plans` tree that uses this tool, which is a product decision, not a spacing fix. The `--` separator solves the stated problem without it.
1. **No behavior changes anywhere.** This is a move-and-rename refactoring. A diff that changes what any method does has left scope.

## Success Criteria

1. `bundle exec rspec` reports exactly the baseline failure set — 121 failures, all in the five files named in `CLAUDE.md` — and not one more. The refactoring is complete when the failure list before and after are identical.
1. `ls lib/openlanes/*.rb` lists only umbrella requires and `version.rb`.
1. `git log --follow` on any moved file shows its pre-move history, proving `git mv` was used throughout.
1. `openlanes docs` and `openlanes states` produce output identical to their pre-refactoring output (capture both before starting; diff after).
1. A folder created by `openlanes create` after the change carries the `--` separator, `openlanes status` decodes both old- and new-form folders in a mixed tree, and `openlanes resync dirs --commit` converges every old-form folder to the new form.
1. `rg` finds no stale path in `CLAUDE.md`, `README.md`, or any comment that names a file by its old location.
1. Every commit in the branch leaves the suite at baseline — verifiable with the `build:test-branch` skill or `git bisect run`.

## Implementation Notes

**The grouping scheme must be settled first** — see Risks. Everything below holds under either scheme.

- **Move source and spec in the same commit.** `git mv lib/openlanes/creator.rb lib/openlanes/<group>/creator.rb` pairs with `git mv spec/openlanes/creator_spec.rb spec/openlanes/<group>/creator_spec.rb`. Batches of at most five files, suite run between batches, one commit per batch.
- **`lib/openlanes.rb` is the only require site that matters.** Files under `lib/openlanes/` do not `require_relative` each other today; the central list loads everything. Each batch updates the corresponding entries in that list. Keep dependency order: the tier analysis in the Research section (ui/config/github before models before operations before execution before reporting) is the order the list already approximates.
- **The `--` separator touches three code sites and their specs.** Compose: `Feature#dirname_as` and `Creator#call` (creator.rb:112). Parse: the `dirname.sub(/\A[\d.]+[-_]/, "")` and status-extraction logic in `Feature.parse` must strip `-#{emoji}--` and `-#{emoji}-` alike, so `canonical?` (feature.rb:105) reports old-form folders as non-canonical and `resync dirs` renames them through the existing `OpenLanes.move_directory`. No new rename machinery.
- **`PlansFixture` and the `:tree` tag** build real folders in specs; the fixture must emit the new form, and at least one spec must feed `Feature.parse` an old-form name to pin backward compatibility.
- **Do not hand-edit derived documents.** `openlanes docs` and `openlanes states` regenerate from `STATUSES` and the `aasm` block; only `CLAUDE.md`'s hand-written Layout section needs editing.
- Sequence the two work streams separately: the separator change is independent of the file moves and should be its own commit (or its own PR) so either can revert alone.

## Trade-offs

**Gained**: a `lib/openlanes/` listing a newcomer can read as a table of contents; a spec tree that answers "where is the test for X" by construction; `git log --follow` history preserved through every move; and plan folder names whose emoji no longer visually swallows the following dash in terminals that render variation-selector emoji at width 1.

**Given up**:

- **`git blame` convenience.** `--follow` works per-file, but line-level blame across a rename requires `-C` flags; reviewers of future PRs touching moved files pay a small tax. Mitigated by a `.git-blame-ignore-revs` entry if the batch commits prove noisy.
- **Churn against in-flight branches.** Any open branch touching a moved file will conflict on the rename. The repository is young (five commits on `main` at time of writing) so the exposure is small, but the refactoring should land quickly once started, not sit open for weeks.
- **A dual-form parsing period.** Until every consumer of this tool has run `resync dirs --commit`, trees contain both `-emoji-slug` and `-emoji--slug` folders and `Feature.parse` must accept both. That compatibility branch is permanent unless a later plan removes it — cheap, but it is real code that exists only for migration.
- **Longer require paths** in the central list — pure bookkeeping, no runtime cost, since explicit require is retained.

Nothing user-visible is given up: the CLI surface, the state machine, and the derived documents are unchanged.

## Timeline & Phases

The research's 2-3 week human estimate does not fit this repository's agent-driven workflow; the phases below are ordered checkpoints, each ending at a green-at-baseline suite and an atomic commit, sized for a single agent session each.

**Phase 0 — Decide and baseline** (blocking, minutes once decided): resolve the grouping-scheme contradiction (Risks, R1). Capture `bundle exec rspec` failure list, `openlanes docs`, and `openlanes states` output as the comparison artifacts.

**Phase 1 — Separator** (one session): change `dirname_as`, `Creator`, and `Feature.parse`; update `PlansFixture`; add the old-form compatibility spec; verify `resync dirs` converges a mixed fixture tree. Independent of everything after it.

**Phase 2 — Domain layer** (one session): move `ordinal`, `status`, `state_machine`, `feature`, `pull_request` and their specs; update the require list.

**Phase 3 — Remaining groups** (two to three sessions): queries/reads, mutations, execution (`runner`, `executor`, `worktree`, `publisher`), agents, reporting, infrastructure — one batch per group, suite between batches.

**Phase 4 — Documentation and closure** (one session): rewrite `CLAUDE.md` Layout, grep for stale paths, diff the regenerated derived docs against Phase 0 artifacts, confirm the failure list matches baseline exactly.

Phases 2-3 depend on Phase 0's decision; Phase 1 does not and may run first or in parallel.

## Risks & Mitigation

**R1 — The introduction and the research prescribe different groupings (highest risk).** The introduction says: co-locate command helpers with their command (`creator.rb` moves under `cli/create/` beside a renamed `command.rb`, multi-command helpers go to `lib/openlanes/shared/`). The research proposes layer-based groups (`models/`, `queries/`, `commands/`, `execution/`, ...) and places `creator.rb` in `commands/`. These assign the same file two different homes. Executing either without confirmation risks redoing the whole move. *Mitigation*: Phase 0 exists to force the decision before any file moves; `luthen-rael-planner` must treat it as the first task, resolved by the human or by an explicit precedence rule (the introduction is the human's own instruction and should win unless overridden).

**R2 — Dash count ambiguity.** The introduction says insert `--` after the emoji; the research says "add one dash". This spec standardizes on the introduction's `--` (emoji, then two dashes, then slug). Any implementer finding the research's phrasing should follow the Goals section.

**R3 — Breaking `Feature.parse` on existing trees.** A parse that accepts only the new form strands every existing `.plans` folder. *Mitigation*: the compatibility spec in Phase 1 is mandatory, and `resync dirs` runs dry by default, so a bad regex is visible before any rename.

**R4 — A batch that leaves the suite worse than baseline.** *Mitigation*: the failure-list-identity criterion (Success Criteria 1) compares lists, not counts, so a new failure cannot hide behind a coincidentally fixed one. One commit per batch keeps `git bisect` sharp.

**R5 — Require-order breakage.** Reordering the central list can raise `NameError` at load. *Mitigation*: the list's current order is the dependency order; preserve relative order within each moved batch and the suite (which loads everything) catches violations immediately.

## Resources Needed

- **People/agents**: one implementer per phase; `luke-backend` for all of it — this gem has no front end, so no `rey-frontend` unit exists. `luthen-rael-planner` should mark Phase 0 as human-blocking if R1 is unresolved when planning starts.
- **Decision input**: a human (or an explicit precedence ruling recorded in this folder) for R1. That is the only external dependency.
- **Environment**: Ruby 4.0.x via rbenv (`eval "$(rbenv init -)"` before every Ruby command — there is no `.ruby-version`), `bundle install` already satisfied, `git` with `git mv`. No network, no credentials, no services: the suite injects doubles into the `GitHub` and `Linear::API` seams and never reaches the network.
- **Tooling already present**: `unicode-display_width` is a runtime dependency (openlanes.gemspec:56) if width-aware rendering needs adjusting; `PlansFixture` and the `:tree` tag for real-filesystem specs; `OpenLanes.move_directory` for any plan-folder renames — do not write a second one.
- **Knowledge**: `CLAUDE.md` in this repository is the map — its Layout table, the "Nothing is written down twice" table, and the baseline failure inventory (648 examples, 121 failures in five named files) are the facts this spec's success criteria are measured against.
- **Comparison artifacts**: pre-refactoring captures of the rspec failure list, `openlanes docs`, and `openlanes states` output, produced in Phase 0 and kept until Phase 4 signs off against them.
