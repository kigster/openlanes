# 007.00 Plan Folder Naming — implementation plan (contract)

Owner: `luke-backend`. Partner: `rey-frontend`.

## Baseline

- `bundle exec rspec` before any change: **2214 examples, 0 failures** (2026-10-13, seed 62909).
- `bundle exec rubocop`: 0 offenses expected (checked at the end).

## Interfaces rey calls

### `Live::Snapshot` — each plan object (`plans[]`, `backlog[]`)

```
status: { key: string, emoji: string, label: string }   # emoji is now the N2 form: ⚪ ⭐ ⭕ 🛑 💤 ⏪ (single code point)
locked: { pid: number, host: string, started_at: string /* ISO-8601 UTC */ } | null
```

- `locked` is `null` when the plan folder has no `locked-by.pid`, or the file is unreadable.
- `locked` is present whether or not the process is alive; the board shows 🔑 whenever it is non-null.
- No errors: the snapshot never fails on a lock file; a malformed file reads as `null`.

### Block emoji

- New: `⭕` (Technical Block, U+2B55), `🛑` (Product Block, U+1F6D1).
- Old, still possible from an unmigrated repo: `⭕️` (U+2B55 U+FE0F), `🅱️` (U+1F171 U+FE0F), bare `🅱`.

## File ownership

| Files | Owner |
| --- | --- |
| `lib/`, `spec/`, `bin/`, `README.md`, `docs/` | luke-backend |
| `web/` | rey-frontend |
| shared files | none |

## Build order

B1 → B2 → (B3 ∥ B4) → B5 → B6 → B7. F1 may start now against the shape above; it needs B4 only to see real data.

## Integration proof

`spec/integration/plan_folder_migration_spec.rb` (B7): temp git repo with old-form folders, driven through the real `exe/openlanes` subprocess, and `Live::Snapshot#to_h` for `locked`. Nothing stubbed.

## Progress

- amended: `locked` is on `plans[]` only, not `backlog[]` — rey's fixture put it there, and a backlog plan has no agent to hold a lock.
- Lock file format (`locked-by.pid`): one JSON line `{"pid":123,"host":"h","started_at":"2026-10-13T09:00:00Z"}`. Unreadable or malformed reads as no lock.

### Round 1 status (luke-backend, 2026-10-13)

- [x] B1 parser: every form, `archived_on`, `LEGACY_EMOJI` (`status.rb`, `feature.rb`). Specs: `feature_spec.rb` table, new `status_spec.rb`.
- [x] B2 writers: `NNN.MM━━<emoji>━━❯<slug>` and dated form; N2 emoji in `STATUSES`; `UI.display_width` counts char+U+FE0F as 2; `bin/plan-number` reads subfolders; index href spec updated; old-name expectations in 20 spec files moved to the new form.
- [x] B4 lock: `Plans::Lock`, dispatcher writes/removes it around the executor (`ensure`), `StateFile.ensure_ignored!` adds `locked-by.pid`, reporter 🔑, snapshot `locked`. Specs: `lock_spec.rb`, reporter, state_file.
- [x] B4 snapshot spec `locked` example.
- [x] B4 remaining spec: `dispatcher_spec.rb` "the plan lock": present during the agent, gone after, gone after a raise, never written on a dry run.
- [x] B3 tree subfolders, `INACTIVE_DIRS`, `list-plans --all`, creator allocation across subfolders, `created:`, `lib/openlanes.rb` ls-tree.
- [x] B5 `resync dirs` moves + `Vcs::RenameDate` + lock clearing.
- [x] B6 M10 `how-to-verify:` migration.
- [x] B7 docs, README, integration spec.
- [x] F1 control room: old and new block emoji, 🔑 for `locked`.
- `bundle exec rspec`: 2305 examples, 0 failures. `bundle exec rubocop`: no offenses.

### Round 2 status (salvage and finish, 2026-10-14)

Round 1's uncommitted work was committed as atomic commits and rebased onto `main`; B3–B7 were then built.

- `bundle exec rspec`: 2355 examples, 0 failures. `bundle exec rubocop`: 310 files, no offenses.
- `web`: vitest 27 files / 293 tests passed; eslint and `tsc -b --noEmit` clean.

Decisions taken where the docs were silent:

- **`created:` is written by `Brief`, not `Creator`.** `Creator` writes no `spec.md`. `Brief#stamp!` merges settings into the frontmatter and restores `created:` after a draft; `create` and the control room's idea dialog both use it, which also fixed the dialog prepending a second frontmatter block.
- **`resync dirs` reads the whole tree, subfolders included** (`Tree#everything`), so it can revive plans and date archived names. Every other reader (runner, snapshot, reporter) keeps the top level only; number allocation, duplicates and `resync prs` use `Tree#taken` / `#everything`.
- **The rename-date probe** is `spec.md`, `plan.md` or `pull-requests.md`, else any file in the folder: a ❌ plan may hold only `discarded.md`.
- **Locked folders** (live local, or any foreign lock) are skipped by `resync dirs` for renames and the M10 rewrite alike.
- **The dispatcher honours other runs' locks** (PR #24 review): a plan whose `locked-by.pid` was written by another live local process, or on another host, is neither dispatched, renamed at start, nor fast-forwarded. Its own locks (`Lock#ours?`) do not keep it out, so a pair still starts together.
- **One lock per plan, counted** (`Engine::PlanLocks`): both halves of a pair share the file; it is written by the first job to start (before its thread, so the next tick sees it) and removed when the last one finishes.
- **M10 cut by node position:** the `how-to-verify:` entry is removed by the line range Psych reports for the key and its value, so blank lines between items and quoted keys are handled. The cut is kept only if the rest reloads as the same mapping less that key; otherwise the spec is left as written.
- **Multi-line checks** (`how-to-verify: |`) are written as one list item with continuation lines indented two spaces (`Spec.list_item`, also used by `Completion` and the prompt), and read back as one item.
- **Readers of the whole tree** also include `linear import`, `linear projects` and `state show|sign --plan`, per N3.
- **M10 reading:** `Spec.parse` reads checks from the frontmatter key and from list items under `## How to tell it's working?`, deduplicated, so `Completion` and the prompt work before and after the migration.
- **Idle message:** with every plan archived the top level is empty; the dispatcher checks the subfolders before saying "no plans yet".
- **Not done here:** this repository's own `.plans/` was not migrated (out of scope); `CLAUDE.md` still shows the old folder example.

