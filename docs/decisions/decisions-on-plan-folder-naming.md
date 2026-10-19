# Decisions on plan folder naming, archiving and locks

Settled 2026-10-13 in a grilling session. N1–N5 are built (plan 007.00). N6–N10 are not built yet; for them this file is the specification the implementing plan works from.

## N1. Folder names have no spaces

`NNN.MM━━<emoji>━━❯<slug>`, for example `028.00━━🟡━━❯state-tax-coverage`.

- `━` is U+2501 and `❯` is U+276F; neither is an emoji. `❯` is always one cell wide. `━` is East Asian "ambiguous" width: one cell by default, two in a terminal set to draw ambiguous characters double width.
- Why: names with spaces need quoting in every shell command and break Tab completion.
- The parser keeps reading the old form, `NNN.MM-<emoji> → <slug>`. `resync dirs` renames old folders to the new form (N5).

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
- Old emoji stay readable, so a folder named with one is still recognised until it is migrated (N5).
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

### N3 amendment, 2026-10-17 (Konstantin Gredeskoul): numbers are allocated across branches, in the primary checkout only

- Why: each checkout saw only its own `.plans`. `main` stopped at 023 while 024–035 lived on an unmerged branch, so `create` on `main` would hand out 024 again.
- New plans (the next major, and retroactive minor slots, including `resync prs` adoption) are created only in the primary checkout. A linked worktree is detected by `git rev-parse --git-dir` differing from `--git-common-dir`; there `create` refuses with "plans are created only in the primary checkout, <path>; this is a worktree of it". `resync prs`, previewing or not, refuses with status 73 when it would adopt. Outside git nothing changes.
- A number is taken if it is in the primary checkout's `.plans` (subfolders included, as above) or in `.plans` on any local branch or `origin/*` remote-tracking branch, read with `git ls-tree`. No fetch: what has not been fetched is not seen.
- Reading the taken numbers and creating the folder happen under an exclusive `flock` on `<git-common-dir>/openlanes-ordinal.lock`, so two creates at once cannot take the same number.
- Built in `Lifecycle::Allocator`; `Plans::Ordinal` stays arithmetic over the list it is given.

## N4. Locks are a file, never part of the name

- While an agent works on a plan, the folder holds `locked-by.pid` with `pid`, `host` and `started_at`. It is git-ignored.
- `list-plans` and the control room show 🔑 for a locked plan.
- `resync dirs` removes a lock whose process is gone, but only for locks taken on this host.
- Rejected alternative: appending `━━🔑` to the folder name. Every agent run would add two tracked renames, paths in prompts, ledgers and mail would change under running agents, and a worktree's lock would not show in the main checkout.

## N5. `resync dirs` does the migration, with no special flag

Plain `openlanes resync dirs` brings every folder to its canonical form, every time it runs:

- renames any folder whose name has a space, or an old emoji, to `NNN.MM━━<emoji>━━❯<slug>` (N1, N2);
- moves ✅ and 😎 plans to `archive/`, 💤 to `deferred/` and ❌ to `abandoned/`, dated by the git commit that last renamed the folder, which is when it reached that state (N3);
- uses `git mv`, so each folder keeps its history;
- previews with `-n` / `--dry-run`, printing old name → new name.

`run` and `start` call `resync dirs` before and after every round, so a repository migrates on its first run without anyone asking. That was chosen over a separate `--from-old-schema` flag.

## N6. Plans declare what they depend on; `blocks` is computed

- `spec.md` frontmatter carries `depends_on: [034, 045]`. `depends_on: []` means "checked, depends on nothing"; a missing key means "not checked yet".
- Only open plans belong in it. A ✅ plan is already on `main`, so depending on it changes nothing, and `[*]` would serialise every plan.
- Only direct dependencies: if 050 needs 045 and 045 needs 034, 050 lists 045. `Plans::Tree` computes the rest.
- `blocks` is never written down. `Plans::Tree` builds it from every `depends_on:`, and `list-plans`, the board, the agents' prompts, priority and the 💣 rule all read that one index. A stored `blocks:` would go stale the first time a dependency was dropped.
- A plan others depend on is assigned before plans nobody waits for.
- A plan whose dependencies are not all ✅ stays where it is; the engine does not start it.

## N7. `ewoki-linker` fills in `depends_on:`

- A new agent, not tied to a state, so no folder name changes. The engine runs it on any plan whose spec lacks the `depends_on:` key, before the plan's first build agent, in every lane: after yoda in `full`, before luthen-rael in `plan`, before r2d2 in `quick`.
- Reads this plan's spec plus the title and goals of every open plan. Writes only `depends_on:`, and a dated ledger note with one reason per dependency.
- A dependency must name what it needs: a table, model, endpoint, module, config, or a product decision. No named thing, no dependency. Touching the same files is a merge risk, not a dependency.
- Haiku, low effort. A plan cannot enter 🟡 Building without the key (invariant). A hand-written `depends_on:` wins; ewoki skips plans that already have the key.
- More than 3 direct dependencies puts the plan under Needs you with a choice: keep them all, split the plan, drop some, or type an answer. The human's pick is kept and not raised again.

## N8. Blocked plans age

| Blocked plan | After | Then |
| --- | --- | --- |
| Others depend on it | 7 days unanswered | becomes 💣, and the run halts |
| Nothing depends on it | 14 days unanswered | moves to `deferred/` as 💤 |

- The clock starts at the later of the date the plan became blocked (the git date of its rename into ⭕ or 🛑) and `plans.aging_since` in `.openlanes.yml`. Setting `aging_since` after a pause keeps the paused weeks from counting.
- 💣 is a new state (U+1F4A3), with the invariant "blocked, has dependents, unanswered past the limit".

## N9. What 💣 halts

- Agents already working finish their current step. Nothing new starts on any plan while a 💣 exists.
- `lanes run` exits non-zero, naming the plan. `lanes start` stays up and idle.
- Answering the block (lando folds it in) returns the plan to its path, and work resumes on the next round.
- Escape hatch: `lanes run --ignore-bombs`, or "Resume anyway for 24 h" in the control room.

## N10. The 💣 notice

- A full-width notice in the control room, split in two: on the left, `blocked.md` rendered as Markdown; on the right, a Markdown answer box with **Respond** at the bottom and **Pause and Discuss** above it.
- Respond writes the answers into `blocked.md`.
- Pause and Discuss stops every agent and opens the copilot with the blocked plan loaded. Re-spec, split or discard happens there, on the human's say-so; nothing changes on disk until then.
