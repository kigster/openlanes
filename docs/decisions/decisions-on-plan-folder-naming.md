# Decisions on plan folder naming, archiving and locks

Settled 2026-10-13 in a grilling session. Not built yet; this file is the specification the implementing plan works from.

## N1. Folder names have no spaces

`NNN.MM━━<emoji>━━❯<slug>`, for example `028.00━━🟡━━❯state-tax-coverage`.

- `━` is U+2501 and `❯` is U+276F. Neither is an emoji, so each is one cell wide. `━` is East Asian "ambiguous" width, so a terminal set to draw ambiguous characters double width draws it two cells wide.
- Why: names with spaces need quoting in every shell command and break Tab completion.
- The parser keeps reading the old form, `NNN.MM-<emoji> → <slug>`. `resync dirs` renames old folders to the new form.

## N2. Every state emoji is one code point that is an emoji by default

| Was | Now | State |
| --- | --- | --- |
| ⚪️ | ⚪ | New |
| ⭐️ | ⭐ | Planned |
| ⭕️ | ⭕ | Technical Block |
| 🅱️ | 🛑 | Product Block |
| ☢️ | 💤 | Deferred |
| 🕰️ | ⏪ | Retroactive |

- Why: emoji that need the variation selector U+FE0F are drawn one cell wide by some programs and two by others. `unicode-display_width` 2.6 counts 🅱️, ☢️ and 🕰️ as one cell while iTerm with Unicode 9 widths draws two, so padded columns came out one cell short.
- A spec asserts every emoji in `STATUSES` is a single code point with emoji presentation by default.
- `UI.display_width` counts any emoji followed by U+FE0F as two cells, for anything that slips through.
- Old emoji stay readable, so a folder named with one is still recognised until `resync dirs` renames it.
- The emoji alone did not explain the misalignment. iTerm also needs "Unicode version 9+ widths" turned on.

## N3. Inactive plans move into subfolders, dated

| State | Folder |
| --- | --- |
| ✅ Approved & Merged, 😎 Deployed | `.plans/archive/` |
| 💤 Deferred | `.plans/deferred/` |
| ❌ Discarded | `.plans/abandoned/` |

- The name gains the date of the move before the slug: `archive/002.00━━✅━━❯[2026-10-13]━━dev-foundation`.
- No year subfolders.
- Plan numbers are allocated across `.plans/` and all three subfolders, so a number is never reused.
- Reviving a plan moves it back into `.plans/` and drops the date.
- `list-plans` shows open plans by default; `--all` includes the subfolders. Linear and `resync` read all of them.
- Why: in equilibris-app, 23 of 37 plans were finished and diluted the 14 still open.
- A plan's age comes from git (the folder's first and last commit) and `state.json`'s `updated_at`. New specs also get a `created:` frontmatter key.

## N4. Locks are a file, never part of the name

- While an agent works on a plan, the folder holds `locked-by.pid` with `pid`, `host` and `started_at`. It is git-ignored.
- `list-plans` and the control room show 🔑 for a locked plan.
- `resync dirs` removes a lock whose process is gone, but only for locks taken on this host.
- Rejected alternative: appending `━━🔑` to the folder name. Every agent run would add two tracked renames, paths in prompts, ledgers and mail would change under running agents, and a worktree's lock would not show in the main checkout.

## Open

- Whether a plan blocked for N days moves to 💤 on its own, or is only offered on a "Stale" card in the control room.
