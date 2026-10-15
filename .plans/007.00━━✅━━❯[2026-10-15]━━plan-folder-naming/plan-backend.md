# 007.00 Plan Folder Naming — back end

Built by `luke-backend`. Units run in the order `B1 → B2 → (B3 ∥ B4) → B5 → B6 → B7`. B3 and B4 may run at the same time: their file sets are disjoint. Every other pair is sequential because it shares a file or a dependency.

Specs build real `.plans` trees through `PlansFixture` and the `:tree` tag; specs that need git history use a temp git repository, never a stubbed `git`.

## B1. Parser reads every form

- **Discipline:** back end.
- **Owns:**
  - `lib/openlanes/plans/feature.rb` (`Feature.parse` only; `plan_dirname` is untouched here)
  - `lib/openlanes/plans/ordinal.rb` (`Ordinal.from_dirname`)
  - `lib/openlanes/plans/status.rb` (a `LEGACY_EMOJI` lookup: old emoji → status key, consulted by `Status.find`/the parser; `STATUSES` emoji unchanged here)
  - `spec/openlanes/plans/feature_spec.rb`, `spec/openlanes/plans/ordinal_spec.rb`, new `spec/openlanes/plans/status_spec.rb`
- **Must not touch:** writers (`plan_dirname`, `dirname_as`), `tree.rb`, `resync.rb`, anything under `web/`.
- **Depends on:** nothing.
- **Shape:** `Feature.parse(path)` returns the same `Feature` for all of:
  `NNN.MM━━<emoji>━━❯<slug>`, `NNN.MM━━<emoji>━━❯[YYYY-MM-DD]━━<slug>`, `NNN.MM-<emoji> → <slug>`, the older `NNN-<emoji>--<slug>` / `-` forms. `Feature` gains `archived_on` (a `Date` or `nil`). Both `🅱️` and bare `🅱` resolve to Product Block; every N2 "Was" emoji resolves to its state, and so does every N2 "Now" emoji (so B2 can swap `STATUSES` without the parser changing again).
- **Done when:** `feature_spec.rb` has a table example over every form above (status, slug, `archived_on`), including the three rows from research §1 that fail today; `ordinal_spec.rb` covers new and old names; `status_spec.rb` asserts old and new emoji resolve to the same status.

## B2. Writers emit the new form; single-code-point emoji

- **Discipline:** back end.
- **Owns:**
  - `lib/openlanes/plans/feature.rb` (`plan_dirname`, `Feature#dirname_as`, emitting `NNN.MM━━<emoji>━━❯<slug>`, and `━━❯[YYYY-MM-DD]━━<slug>` when `archived_on` is set)
  - `lib/openlanes/plans/status.rb` (`STATUSES` emoji per N2: ⚪ ⭐ ⭕ 🛑 💤 ⏪; the old ones move into `LEGACY_EMOJI`)
  - `lib/openlanes/support/ui.rb` (`UI.display_width`: any char followed by U+FE0F counts two cells)
  - `bin/plan-number` (name parsing only: accept the new form)
  - `spec/openlanes/plans/status_spec.rb`, `spec/openlanes/plans/feature_spec.rb`, `spec/openlanes/plans/index_spec.rb`, `spec/openlanes/support/ui_spec.rb` (create if missing), `spec/bin/plan_number_spec.rb` (or wherever `bin/plan-number` is specced today)
  - every existing spec and fixture that hard-codes an old folder name or old emoji and would otherwise fail (update the expectation, not the behaviour)
- **Must not touch:** `tree.rb`, `creator.rb`, `resync.rb`, `lib/openlanes.rb`, `web/`.
- **Depends on:** B1 (same files: `feature.rb`, `status.rb`, `status_spec.rb`, `feature_spec.rb`).
- **Also verifies:** `plans/index.rb:184` percent-encodes `━` and `❯` into a link that resolves; an `index_spec.rb` example asserts it. Fix only if it does not.
- **Done when:** `status_spec.rb` iterates `STATUSES` asserting one code point, no U+FE0F, emoji presentation by default; `feature_spec.rb` covers `plan_dirname` for every status and the dated form round-trips through `Feature.parse`; `ui_spec.rb` asserts `🅱️`, `☢️`, `🕰️` measure 2; `bundle exec rspec` is green.

## B3. Tree walks subfolders; numbers span them; `list-plans --all`; `created:`

- **Discipline:** back end.
- **Owns:**
  - `lib/openlanes/plans/tree.rb` (`Tree#directories` also reads `archive/`, `deferred/`, `abandoned/`; a `Tree.new(..., all: false)` default hides them; `INACTIVE_DIRS = { archive: …, deferred: …, abandoned: … }` keyed by status key, the one table B5 reads)
  - `lib/openlanes/lifecycle/creator.rb` (number allocation at `:58` covers top level and subfolders; writes `created: YYYY-MM-DD` frontmatter)
  - `lib/openlanes/lifecycle/brief.rb` (`created:` in the scaffolded `spec.md`)
  - `lib/openlanes.rb` (`:133`, `ls-tree` covers the subfolders)
  - `bin/plan-number` (`:115`, search depth 2 over the three subfolders)
  - `lib/openlanes/cli/list_plans/list_plans.rb` (`--all` option; open plans first, then each subfolder, number order within each group)
  - specs: `spec/openlanes/plans/tree_spec.rb` (create), `spec/openlanes/lifecycle/creator_spec.rb`, `spec/openlanes/lifecycle/brief_spec.rb`, `spec/openlanes/cli/list_plans_spec.rb`
- **Must not touch:** `presentation/reporter.rb` (B4), `resync.rb`, `engine/`, `web/`.
- **Depends on:** B2 (`bin/plan-number` is shared; dated names must parse and emit).
- **Done when:** `tree_spec.rb` (`:tree`) has one plan in each subfolder, hidden by default, visible with `all: true`; `creator_spec.rb` allocates past a number that lives only in `archive/`, and `lib/openlanes.rb`'s allocator has the same example; `list_plans_spec.rb` shows `--all` output order; `brief_spec.rb` asserts `created:`.

## B4. Lock file and 🔑

- **Discipline:** back end.
- **Owns:**
  - new `lib/openlanes/plans/lock.rb`: `Plans::Lock = Data.define(:pid, :host, :started_at)` with `Lock.read(dir)`, `Lock.write(dir)` (current pid, `Socket.gethostname`, now), `Lock.remove(dir)`, `#local?`, `#alive?` (`local? && Process.kill(0, pid)` succeeds), `FILENAME = "locked-by.pid"`
  - `lib/openlanes/engine/dispatcher.rb` (write when an agent starts on a plan, remove in an `ensure` when it ends)
  - `lib/openlanes/engine/state_file.rb` (`ensure_ignored!` adds `locked-by.pid`)
  - `lib/openlanes/presentation/reporter.rb` (🔑 for a locked plan)
  - `lib/openlanes/live/snapshot.rb` (each plan gains `locked: { pid:, host:, started_at: }` or `null`; the shape F1 reads)
  - specs: `spec/openlanes/plans/lock_spec.rb` (create), `spec/openlanes/engine/dispatcher_spec.rb`, `spec/openlanes/engine/state_file_spec.rb`, `spec/openlanes/presentation/reporter_spec.rb`, the snapshot spec under `spec/openlanes/live/`
- **Must not touch:** `tree.rb`, `cli/list_plans/`, `resync.rb`, `web/`.
- **Depends on:** B2. Runs beside B3.
- **Done when:** `lock_spec.rb` covers write/read/remove and `alive?` for same host dead, same host alive, other host; `dispatcher_spec.rb` sees the file during the agent and not after, including after a raised error; `state_file_spec.rb` asserts `git check-ignore locked-by.pid` succeeds in a temp repo; `reporter_spec.rb` shows 🔑; the snapshot spec shows `locked`. The folder name never changes while locked.

## B5. `resync dirs` migrates names and locations

- **Discipline:** back end.
- **Owns:**
  - `lib/openlanes/lifecycle/resync.rb` (dirs half)
  - new `lib/openlanes/vcs/rename_date.rb`: `Vcs::RenameDate.for(dir) → Date`, from `git log --follow --diff-filter=R --format=%cI -1 -- <dir>/spec.md` (first file present), falling back to `state.json` `updated_at`, then today
  - specs: `spec/openlanes/lifecycle/resync/dirs_spec.rb`, `spec/openlanes/vcs/rename_date_spec.rb` (create)
- **Must not touch:** `feature.rb`, `status.rb`, `tree.rb`, `lock.rb`, `spec.rb`.
- **Depends on:** B3 (subfolder table, tree walk) and B4 (`Lock`).
- **Behaviour:** one pass, idempotent, with `git mv` via `OpenLanes.move_directory`:
  - rename any folder with a space or old emoji to the new form;
  - move ✅ 😎 → `archive/`, 💤 → `deferred/`, ❌ → `abandoned/`, with `[date]` from `RenameDate`;
  - a plan in a subfolder whose state is no longer inactive moves back to `.plans/` and drops its date (this is how revival works; the state machine still renames in place);
  - remove `locked-by.pid` only when `Lock#local?` and not `#alive?`; report other-host locks, never clear them;
  - `-n` prints `old → new` per folder and changes nothing.
- **Done when:** `dirs_spec.rb` runs on a temp git fixture with old names in every form and asserts the moves, the dates, `-n` changing nothing, a second run reporting nothing, revival, and the three lock cases; `rename_date_spec.rb` does a real `git mv` + commit and reads the date back, plus both fallbacks.

## B6. M10: `how-to-verify:` moves into the body

- **Discipline:** back end.
- **Owns:**
  - `lib/openlanes/plans/spec.rb` (a `Spec.migrate_how_to_verify(text) → text`: removes the frontmatter key, appends its items under `## How to tell it's working?`, creating the heading at the end if absent, appending to it if present)
  - `lib/openlanes/lifecycle/resync.rb` (calls it per folder; reported and previewed like a rename)
  - `lib/openlanes/lifecycle/completion.rb` and `lib/openlanes/execution/prompt.rb` (read the section, keep reading the key for unmigrated specs)
  - specs: `spec/openlanes/plans/spec_spec.rb`, `spec/openlanes/lifecycle/resync/dirs_spec.rb`, `spec/openlanes/lifecycle/completion_spec.rb`
- **Must not touch:** `feature.rb`, `tree.rb`, `lock.rb`.
- **Depends on:** B5 (same files: `resync.rb`, `dirs_spec.rb`).
- **Done when:** `spec_spec.rb` has before/after `spec.md` pairs (heading absent, heading present, key absent = untouched); `dirs_spec.rb` asserts the migration runs, previews under `-n`, and is a no-op the second time; `completion_spec.rb` passes with both shapes.

## B7. Docs, README, and the integration check

- **Discipline:** back end.
- **Owns:**
  - `lib/openlanes/presentation/documentation.rb` (folder-name examples from `plan_dirname`, subfolders, the lock file)
  - `README.md`, `docs/decisions/decisions-on-plan-folder-naming.md` (drop "Not built yet" for N1–N5 only)
  - new `spec/integration/plan_folder_migration_spec.rb`
  - `spec/openlanes/presentation/documentation_spec.rb`
- **Must not touch:** anything B1–B6 own, except to fix a defect the integration spec exposes (then name the unit in the commit).
- **Depends on:** B6.
- **Integration check (nothing stubbed):** in a temp git repository, build `.plans` with old-form folders (`-`/`--`, `→`, every old emoji, one ✅, one 💤, one ❌, one spec with `how-to-verify:`), commit, then run the real `exe/openlanes` as a subprocess:
  1. `resync dirs -n` prints every rename and move, and `git status` is clean;
  2. `resync dirs` performs them; `git log --follow` on a moved `spec.md` reaches the pre-move commit;
  3. `ls .plans` shows only open plans, no name contains a space;
  4. `list-plans` hides the archived; `list-plans --all` shows them with their dates;
  5. `create` allocates a number above the one in `archive/`;
  6. writing a `locked-by.pid` with this pid shows 🔑 in `list-plans` and `locked` in `Live::Snapshot`'s JSON, and the folder name is unchanged;
  7. a second `resync dirs` changes nothing.
- **Done when:** `plan_folder_migration_spec.rb` passes; `documentation_spec.rb` asserts no folder-name example contains `→`; `bundle exec rspec` 0 failures; `just lint` zero offenses.
