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
- [ ] B4 remaining spec: `dispatcher_spec.rb` (file present during the agent, gone after, incl. raised error).
- [ ] B3 tree subfolders, `INACTIVE_DIRS`, `list-plans --all`, creator allocation across subfolders, `created:`, `lib/openlanes.rb` ls-tree.
- [ ] B5 `resync dirs` moves + `Vcs::RenameDate` + lock clearing.
- [ ] B6 M10 `how-to-verify:` migration.
- [ ] B7 docs, README, integration spec.
- `bundle exec rspec`: 2305 examples, 0 failures. `bundle exec rubocop`: no offenses.
