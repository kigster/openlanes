# Abandon, Discard and Trash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person clear any plan out of the way from any state, with a recorded reason, without stranding its dependents.

**Architecture:** Two new states plus a changed ❌, each justified by a non-empty reason file. One `Lifecycle::Removal` operation writes the file, rewires the graph and moves the folder. `resync dirs` reaches the same rewiring and move through `best_fit`.

**Tech Stack:** Ruby 4.0.6, dry-cli, aasm, tty-prompt, RSpec with `PlansFixture`.

**Spec:** `docs/decisions/decisions-on-plan-abandon-discard-trash.md` (X1 to X9). Read it first.

## Global Constraints

- Abandoned is `:abandoned`, 👎, `abandoned/`. Discarded is `:discarded`, ❌, `discarded/`. Trashed is `:trashed`, 🚮, `trashed/`.
- Reason files: `abandoned-reason.md`, `discarded-reason.md`, `trashed-reason.md`. `discarded.md` still qualifies ❌.
- Preference among them: trashed, then discarded, then abandoned, ahead of every other state.
- Whitespace-only reason files do not qualify.
- Every command writes when run; `-n` / `--dry-run` previews. STDOUT carries the report, STDERR the prompts.
- Run Ruby through `eval "$(rbenv init -)"`. Keep `bundle exec rubocop` at zero offenses.
- Commit subjects: 50 characters, imperative, capitalized, no period. No attribution lines.

## Review Focus

- Ctrl-C or a blank answer halfway through the prompts: all answers are collected before anything is written, so nothing moves.
- A dependent whose `spec.md` has invalid YAML or no frontmatter: reported and left unchanged, and the plan still moves.
- A reason containing quotes, newlines or Markdown: written literally to the reason file.
- A plan with an unanswered `blocked.md` or a legacy-spelled folder name: lands in the right directory with the current spelling.
- The target folder name already exists: that plan is reported as failed and the others still proceed, with a non-zero exit.

---

## Frontend

No units. This plan is CLI and library work only; there is no web or interface surface, so backend-coder owns every task.

## Backend

### Task 1: The states

**Files:**
- Modify: `lib/openlanes/plans/status.rb`, `state_machine.rb`, `tree.rb`, `dependencies.rb`, `index.rb`
- Modify: `lib/openlanes/lifecycle/aging.rb`, `lib/openlanes/live/snapshot.rb`, `lib/openlanes/linear/mapping.rb`, `lib/openlanes/vcs/rename_date.rb`
- Test: `spec/openlanes/plans/state_machine_spec.rb`, `dependencies_spec.rb`, `status_spec.rb`, `tree_spec.rb`

**Interfaces:**
- Produces: `Plans::REMOVED = %i[abandoned discarded trashed]`, `Plans.reason_file(key) -> String`, `Plans.reason_given?(subject, key) -> Boolean`, events `abandon`, `discard`, `trash`, `Tree::INACTIVE_DIRS` with all three directories.

- [ ] **Step 1: Write failing specs**

Assert: 🚮 is the only terminal state (replaces the existing "discarded the only terminal state" example); `inbound[:trashed]` is every other state; `inbound[:discarded]` excludes `trashed`; `inbound[:abandoned]` excludes `discarded` and `trashed`. A folder with `trashed-reason.md` holding `"  \n"` does not satisfy `:trashed`; one holding `"done"` does, and `best_fit` returns it even beside an open `blocked.md`. With both trash and discard reasons, `best_fit` is `:trashed`. `discarded.md` satisfies `:discarded`. `Dependencies#waiting_on` omits an entry naming a plan in any `REMOVED` state, and `#closed` includes it. `Tree.subfolder_for` maps the three keys to their directories.

- [ ] **Step 2: Run `bundle exec rspec spec/openlanes/plans` and confirm the new examples fail**

- [ ] **Step 3: Implement**

Status entries have `requires: []` and a reason-file invariant, because `requires` cannot say "either file" for ❌ and must not count blank files. Rewrite ❌'s note per X5. Add events per X8 (they are not added to `BLOCKABLE`). Prepend the three to `PREFERENCE` and add them to `SETTLED`. Keep `Dependencies::DONE` as is, because `Engine` and others read it as "shipped"; add a separate `met?` used by `waiting_on` and `closed`. Add `abandoned` and `trashed` to `Aging::CLOSED` and `Snapshot::FINISHED`. Add both to Linear `PLACEMENTS` as `canceled`, with labels `abandoned` and `trashed`. Name the three reason files in `ARTIFACT_NAMES`, and follow them in `rename_date.rb`.

- [ ] **Step 4: Run `just test` until green, then `just update-workflow`, `just update-architecture`, and `./exe/openlanes states`**

- [ ] **Step 5: Commit**: `Add abandoned and trashed plan states`

### Task 2: Rewire dependents

**Files:**
- Create: `lib/openlanes/lifecycle/rewiring.rb`
- Modify: `lib/openlanes/plans/spec.rb`, `lib/openlanes/lifecycle.rb`
- Test: `spec/openlanes/lifecycle/rewiring_spec.rb`

**Interfaces:**
- Consumes: `Plans::REMOVED`.
- Produces: `Plans::Spec.with_depends_on(text, list) -> String`; `Lifecycle::Rewiring.new(tree:).plan(removed_ordinals) -> Array<Edit>`; `Lifecycle::Rewiring#apply(edits) -> Array<Edit>`; `Edit = Data.define(:ordinal, :path, :before, :after, :problem)` with `to_s` of `"A: B → C, D"`.

- [ ] **Step 1: Write failing specs using real trees**

`A→B→C`, remove B: A is `["C"]`. `A→B`, `B→C,D`: A is `["C","D"]`, sorted. `A→B→C→D`, remove B and C in either order: A is `["D"]`. `A→B`, B has none: A is `[none]`. B→C where C is ✅: A loses the entry. `A→B→A`, remove B: A's entry is dropped, never `A→A`. A in `deferred/` is rewritten; A in `archive/` is not. Only the `depends_on:` line differs afterward, comments included. Invalid YAML in A: an `Edit` with `problem` set and the file untouched.

- [ ] **Step 2: Run the file and confirm it fails**

- [ ] **Step 3: Implement**

Compute the closure over the snapshot of the graph before writing anything, so order cannot matter:

```ruby
expand = lambda do |entry, seen|
  next [entry] unless removed.include?(entry)
  next [] if seen.include?(entry)
  edges(entry).flat_map { expand.call(it, seen + [entry]) }
end
```

Filter out done entries and the plan itself, then `uniq.sort`. An empty result writes `[none]`, which `Spec` already reads as "looked and found nothing". Use `Tree#everything` for the graph.

- [ ] **Step 4: Run the file until green**

- [ ] **Step 5: Commit**: `Rewire dependents around a removed plan`

### Task 3: The removal operation

**Files:**
- Create: `lib/openlanes/lifecycle/removal.rb`, `lib/openlanes/plans/removed_readme.rb`
- Modify: `lib/openlanes/lifecycle.rb`
- Test: `spec/openlanes/lifecycle/removal_spec.rb`

**Interfaces:**
- Consumes: `Rewiring`, `Plans.reason_file`.
- Produces: `Lifecycle.removal(tree:, to:) -> Removal`; `Removal#call(reasons, dry_run:) -> Result`, where `reasons` is `{ ordinal => String }`; `Result = Data.define(:moved, :skipped, :refused, :edits, :open_prs)`; `Plans::RemovedReadme.ensure(dir)`.

- [ ] **Step 1: Write failing specs**

From ⭕ with an open `blocked.md`, 🏁 with an open PR, and ⚪ with no `plan.md`, a trash lands in `trashed/` dated with 🚮. `trashed-reason.md` holds the reason, today's date, the previous state and the rewrites. A plan already in the state is in `skipped`, with its file unchanged. A plan under `discarded/` can be trashed and keeps `discarded-reason.md`. A held `Plans::Lock` puts the plan in `refused` while the others move. A taken target name goes to `refused`. Open PRs are returned in `open_prs`. `dry_run: true` leaves the disk identical. `README.md` appears in the new directory, and `Tree#skipped` does not list it.

- [ ] **Step 2: Run the file and confirm it fails**

- [ ] **Step 3: Implement**

Write the reason file, then rewire, then move through `Resync::Dirs`'s own placement (expose `home_for` and `rename` rather than copying them) so the date and `state.json` handling stay single-sourced. If the move fails, delete the reason file only if this call wrote it, and do not apply the edits; so compute edits first and apply them last. The README text states the X1 table once, in `RemovedReadme`.

- [ ] **Step 4: Run the file until green**

- [ ] **Step 5: Commit**: `Add the plan removal operation`

### Task 4: resync dirs

**Files:**
- Modify: `lib/openlanes/lifecycle/resync.rb`
- Test: `spec/openlanes/lifecycle/resync/dirs_spec.rb`, `spec/integration/plan_folder_migration_spec.rb`

**Interfaces:**
- Consumes: `Rewiring`, `RemovedReadme`.

- [ ] **Step 1: Write failing specs**

An active folder with a non-empty `trashed-reason.md` moves to `trashed/` as 🚮, and its dependents are rewired. A ❌ in `abandoned/` moves to `discarded/`, keeping its date. A 👎 in `abandoned/` stays. Deleting the reason file brings the plan back to the top level on its best fit. A dry run writes nothing and lists the edits.

- [ ] **Step 2: Run the file and confirm it fails**

- [ ] **Step 3: Implement**

Rewire when a change's `to` is in `REMOVED` and its `from` is not. Keep an existing date when moving between inactive directories: today `home_for` keeps it only within the same parent, which would re-date the migrated plans.

- [ ] **Step 4: Run the file until green**

- [ ] **Step 5: Commit**: `Move plans by reason file in resync dirs`

### Task 5: The commands

**Files:**
- Create: `lib/openlanes/cli/list_plans/removal_command.rb`, `abandon.rb`, `discard.rb`, `trash.rb`, `lib/openlanes/lifecycle/reason_interview.rb`
- Modify: `lib/openlanes/cli.rb`
- Test: `spec/openlanes/cli/list_plans/removal_spec.rb`, `spec/openlanes/lifecycle/reason_interview_spec.rb`

**Interfaces:**
- Consumes: `Lifecycle.removal`.
- Produces: `ReasonInterview.new(prompt:, verb:, choices:).ask(subjects) -> { ordinal => String }`, and `register "plans abandon"`, `"plans discard"`, `"plans trash"` beside `register "plans"`.

- [ ] **Step 1: Write failing specs**

`--reason` asks nothing and applies to all listed plans. An unknown id exits non-zero with nothing moved. No terminal and no `--reason` exits non-zero with nothing moved. `-n` writes nothing. A blank free-text answer asks again. Trash's select offers exactly the five X3 choices, with the first as default, and "Some other reason" asks `Reason for scrapping this plan:`. The interview returns all answers before any write. `ol plans --all` still works, and bare `ol plans` still prints the table. Output names each rewrite and each open PR. Exit is non-zero when anything was refused.

- [ ] **Step 2: Run the files and confirm they fail**

- [ ] **Step 3: Implement**

Follow `WorktreePrune` for the shape, `dry_run_option` and `refuse`. Resolve ids with `tree.everything.find`. Prompt with `Setup::SpacedPrompt` around `TTY::Prompt.new(output: $stderr)`, as `init` does.

- [ ] **Step 4: Run the files until green, then check `./exe/openlanes plans trash --help`**

- [ ] **Step 5: Commit**: `Add plans abandon, discard and trash commands`

### Task 6: The PR watcher and the docs

**Files:**
- Modify: `lib/openlanes/engine/pr_outcomes.rb`, `skills/openlanes-documents/SKILL.md`, `skills/openlanes-documents/references/closing-templates.md`, `skills/openlanes/SKILL.md`, `lib/openlanes/cli/list_plans/list_plans.rb`, `.plans/README.md`
- Test: `spec/openlanes/engine/pr_outcomes_spec.rb`

- [ ] **Step 1: Write failing specs**

A close with nothing open writes `discarded-reason.md`. A merge or close for a plan in `trashed/`, `discarded/` or `abandoned/` updates its `pull-requests.md` row, leaves the folder where it is, and fires no merge side effects.

- [ ] **Step 2: Run the file and confirm it fails**

- [ ] **Step 3: Implement**

`find` reads `Tree.new(dir:, all: true)`. Return early after `record` when the subject's status is in `REMOVED`. Update the skills and the `--all` help text to the new directories.

- [ ] **Step 4: Run `just lint && just test`; both must be green**

- [ ] **Step 5: Commit**: `Keep removed plans' PR rows current`

---

### B1 (answered) — Redis outage specs fail on a locked string

The full suite must exit 0, but three Redis outage specs fail with `RuntimeError: can't modify string; temporarily locked`. The error comes from `Live::Store#call` via `RunRecord#read_redis` in `Dispatcher#tick`, which suggests one `RedisClient` connection read from two threads at once. These specs do not touch plan 059's code. Failing specs: `spec/openlanes/engine/redis_outage_spec.rb:37`, `spec/openlanes/live/redis_outage_integration_spec.rb:72` and `:77`.

Options offered: (a) fix it in a separate plan and name the three as baseline, (recommended) (b) fix it inside this plan, (c) treat it as environmental and rerun on CI.

### D1 (decision) — Fix the Redis race inside this plan

Answered:

- 2026-11-12, 20:53 PST
- By hermes

Option (b). This plan widens its scope into `lib/openlanes/live/`. The next round fixes the Redis race there, so `bundle exec rspec` exits 0 with no named baseline failures.

## How to test

Run every command from the repository root, after `eval "$(rbenv init -)"`.

- `bundle exec rspec`: 0 failures. Pending examples are only the ones skipped because no Redis or tool is available.
- `bundle exec rubocop`: no offenses.
- The states (Task 1): `bundle exec rspec spec/openlanes/plans` passes, and `./exe/openlanes states` draws 👎 Abandoned, ❌ Discarded and 🚮 Trashed, with 🚮 as the only terminal state.
- Rewiring (Task 2): `bundle exec rspec spec/openlanes/lifecycle/rewiring_spec.rb` passes: removing B from A→B→C leaves A depending on C, a cycle through B drops the entry, and a dependent with invalid YAML is reported and left unchanged.
- Removal (Task 3): `bundle exec rspec spec/openlanes/lifecycle/removal_spec.rb spec/openlanes/lifecycle/removal_review_spec.rb` passes: a plan lands in `abandoned/`, `discarded/` or `trashed/` with its reason file, a held lock or a taken name puts it in `refused` while the others move, and `dry_run: true` leaves the disk unchanged.
- resync dirs (Task 4): `bundle exec rspec spec/openlanes/lifecycle/resync/dirs_spec.rb spec/integration/plan_folder_migration_spec.rb` passes: a folder with a non-empty `trashed-reason.md` moves to `trashed/`, and a ❌ still in `abandoned/` moves to `discarded/` and keeps its date.
- The commands (Task 5): `bundle exec rspec spec/openlanes/cli/removal_command_spec.rb spec/openlanes/lifecycle/reason_interview_spec.rb` passes. `./exe/openlanes plans trash --help`, `plans abandon --help` and `plans discard --help` each show `IDS...`, `--reason` and `-n, --dry-run`. Bare `./exe/openlanes plans` still prints the table.
- By hand, in a project with plans on `main`: `ol plans trash -n <id> --reason "built elsewhere"` prints the move and every `depends_on:` rewrite and writes nothing. The same command without `-n` moves the folder under `.plans/trashed/` with a 🚮 name, writes `trashed-reason.md` with the reason, and rewrites each dependent's `depends_on:`. An unknown id exits non-zero and moves nothing.
- The PR watcher (Task 6): `bundle exec rspec spec/openlanes/engine/pr_outcomes_spec.rb` passes: a closed PR writes `discarded-reason.md`, and a plan already removed keeps its folder and gets only its `pull-requests.md` row updated.
- The Redis race (D1): `bundle exec rspec spec/openlanes/live/store_spec.rb spec/openlanes/engine/redis_outage_spec.rb spec/openlanes/live/redis_outage_integration_spec.rb spec/openlanes/thread_safety_inventory_spec.rb` passes with Redis running locally, including "answers callers on several threads at once". Without Redis these examples skip.
