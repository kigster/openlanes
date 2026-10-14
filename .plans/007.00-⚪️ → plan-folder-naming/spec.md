---
depends_on: []
---

# Plan Folder Naming

## What we are trying to achieve

Folder names without spaces (`NNN.MM━━<emoji>━━❯<slug>`), single-code-point state emoji, inactive plans in dated `archive/`, `deferred/` and `abandoned/` subfolders, and locks in a git-ignored `locked-by.pid`. `resync dirs` migrates every repository on its first run, including moving a spec's `how-to-verify:` key into `## How to tell it's working?` (M10).

## Why it matters

Names with spaces need quoting everywhere. Six emoji (⚪️ ⭐️ ⭕️ 🅱️ ☢️ 🕰️) need a variation selector, so `unicode-display_width` counts some as one cell while terminals draw two, and padded columns come out short. Finished plans crowd out open ones: equilibris-app had 23 finished among 37.

## What already exists

- Decisions N1–N5 and N4 (locks) in `docs/decisions/decisions-on-plan-folder-naming.md`; the README already documents the convention.
- `lib/openlanes/plans/feature.rb`: `plan_dirname` and the folder-name parser.
- `lib/openlanes/plans/status.rb`: `STATUSES` and their emoji.
- `lib/openlanes/lifecycle/resync.rb`: `resync dirs`.
- `lib/openlanes/support/ui.rb`: `UI.display_width`, `UI.fit`.
- `lib/openlanes/lifecycle/creator.rb`: allocates the next number.

## What research needs to settle

- Every place that builds or parses a folder name, including specs, the web board and the Linear export.
- How `Plans::Tree` walks the three subfolders, and how `list-plans --all` shows them.
- Reading the date for archived plans from git (`git log --follow --diff-filter=R`).
- Lock contents and the host check.

## How to tell it's working?

- In a copy of a repository with old names, `lanes resync dirs -n` lists every rename and move; without `-n` it performs them with `git mv`.
- `ls .plans` shows only open plans, with no spaces in any name.
- A spec asserts every `STATUSES` emoji is a single code point.
- While an agent runs, `list-plans` shows 🔑 on its plan, and the folder name does not change.

## What we are trying to achieve


## Why it matters


## What already exists


## What research needs to settle

