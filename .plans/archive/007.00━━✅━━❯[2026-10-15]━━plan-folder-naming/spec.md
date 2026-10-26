---
depends_on: []
---

# Plan Folder Naming

## What we are trying to achieve

Folder names without spaces (`NNN.MM━━<emoji>━━❯<slug>`), single-code-point state emoji, inactive plans in dated `archive/`, `deferred/` and `abandoned/` subfolders, and locks in a git-ignored `locked-by.pid`. `resync dirs` migrates every repository on its first run, including moving a spec's `how-to-verify:` key into `## How to tell it's working?` (M10).

## Why it matters

Names with spaces need quoting everywhere. Six emoji (⚪️ ⭐️ ⭕️ 🅱️ ☢️ 🕰️) need a variation selector, so `unicode-display_width` counts some as one cell while terminals draw two, and padded columns come out short. Finished plans crowd out open ones: equilibris-app had 23 finished among 37.

## What already exists

- Decisions N1–N5 in `docs/decisions/decisions-on-plan-folder-naming.md`; the README already documents the convention. N6–N10 in the same file are a different feature (dependencies, aging, 💣) and are not part of this plan.
- `lib/openlanes/plans/feature.rb`: `plan_dirname` and the folder-name parser.
- `lib/openlanes/plans/status.rb`: `STATUSES` and their emoji.
- `lib/openlanes/lifecycle/resync.rb`: `resync dirs`.
- `lib/openlanes/support/ui.rb`: `UI.display_width`, `UI.fit`.
- `lib/openlanes/lifecycle/creator.rb`: allocates the next number.

## What research needs to settle

Settled in `## Research` below: call sites (§1), subfolder walking (§2), git dates (§3), lock contents (§4).

## How to tell it's working?

- In a copy of a repository with old names, `lanes resync dirs -n` lists every rename and move; without `-n` it performs them with `git mv`.
- `ls .plans` shows only open plans, with no spaces in any name.
- A spec asserts every `STATUSES` emoji is a single code point.
- While an agent runs, `list-plans` shows 🔑 on its plan, and the folder name does not change.

## Framing

Two ways to cut the problem:

1. **One schema change, shipped whole.** Name form, emoji, subfolders, locks and migration land together, because `resync dirs` must know all of them to migrate in one pass.
1. **Layers, each shippable.** Parser reads both forms → writers emit the new form → `Tree` walks subfolders → locks → migration last.

Chosen: **2, layers, with migration last.** Research §1 measured that `Feature.parse` does not read the new form today; migrating before the parser is fixed would make `resync dirs` call every new name non-canonical. The layers are also the order the work units must run in.

## Goal

After this ships, a plan folder name contains no spaces and no emoji that needs a variation selector, finished/deferred/discarded plans no longer sit beside open ones, an agent's lock is visible as 🔑 without renaming the folder, and `openlanes resync dirs` upgrades any existing repository to that layout, keeping each folder's git history.

## Non-Goals

- No year subfolders under `archive/` (N3).
- No folder rename to show a lock; the lock is a file (N4).
- No `--from-old-schema` or `--apply` flag; plain `resync dirs` migrates (N5).
- No `depends_on:` computation, `ewoki-linker`, plan aging or 💣 state (N6–N10).
- No change to the web board's agent-name parsing (research §1: unaffected).
- No automatic clearing of a lock taken on another host.
- No terminal setting changes; iTerm "Unicode 9+ widths" stays the user's choice.

## In scope

Each item names its check.

1. `Plans.plan_dirname` emits `NNN.MM━━<emoji>━━❯<slug>`. *Check:* spec on `plan_dirname` for every status.
1. `Feature.parse` reads the new form and the old form (`NNN.MM-<emoji> → <slug>` and the older `-`/`--` forms), including the optional `[YYYY-MM-DD]━━` date prefix. *Check:* table spec asserting status and slug for each form; today's three failing rows from research §1 pass.
1. `Ordinal.from_dirname` and `bin/plan-number` accept the new form. *Check:* specs with new and old names.
1. `STATUSES` use single-code-point emoji per N2 (⚪ ⭐ ⭕ 🛑 💤 ⏪); old emoji still resolve to the same status when parsing. *Check:* spec iterating `STATUSES` asserting one code point and no U+FE0F; spec that an old-emoji folder parses.
1. `UI.display_width` counts any char followed by U+FE0F as two cells. *Check:* spec with `🅱️`, `☢️`, `🕰️`.
1. `Tree` walks `archive/`, `deferred/`, `abandoned/`; default views exclude them. *Check:* `:tree` spec with one plan in each.
1. `list-plans --all` includes the subfolders. *Check:* CLI spec.
1. Number allocation covers the top level and all three subfolders in `creator.rb:58`, `bin/plan-number:115` and `lib/openlanes.rb:133`. *Check:* spec where the highest number lives in `archive/`.
1. Archived names carry `[YYYY-MM-DD]` taken from `git log --follow --diff-filter=R --format=%cI` on a file in the folder (research §3). *Check:* spec in a temp git repo that does the move and reads the date.
1. `locked-by.pid` holds `pid`, `host`, `started_at`; written when an agent starts on a plan, removed when it ends, git-ignored via the existing `ensure_ignored!` pattern. *Check:* executor/dispatcher spec; `git check-ignore`.
1. `list-plans` shows 🔑 for a locked plan. *Check:* reporter spec.
1. `resync dirs` removes a lock only when `host` equals this host and `Process.kill(0, pid)` fails. *Check:* three specs: same host dead, same host alive, other host.
1. `resync dirs` renames space/old-emoji folders and moves ✅ 😎 → `archive/`, 💤 → `deferred/`, ❌ → `abandoned/` with `git mv`; `-n` prints old → new and changes nothing; a second run is a no-op. *Check:* spec on a fixture repo with old names; idempotence spec.
1. `resync dirs` moves a spec's `how-to-verify:` frontmatter key into a `## How to tell it's working?` section (M10). *Check:* spec with a before/after spec.md.
1. `openlanes docs` and `README.md` show the new form. *Check:* regenerated output has no `→` in a folder-name example.
1. `bundle exec rspec` stays at 0 failures and `just lint` at zero offenses. *Check:* both commands.

## Out of scope

| Item | Reason |
| --- | --- |
| N6–N10 (`depends_on`, ewoki, aging, 💣) | Separate feature in the same decisions file; no folder-name dependency. |
| Web board changes | Research §1: splits agent names, not folder names. |
| Clearing locks from other hosts | `Process.kill(0)` is meaningless across hosts (research "could not be settled" 3). |
| Shallow-clone support for git dates | Not verified; no CI in this repo (research §3). |
| Linear export schema changes | `linear.md` lives inside the folder and moves with it (research §1). |

## Back end / front end

`backend-coder` builds every item; `frontend-coder` has almost nothing because the web board does not parse folder names.

| Item | Half |
| --- | --- |
| Parser, `plan_dirname`, `Ordinal`, `STATUSES`, `UI.display_width` | back end (`backend-coder`) |
| `Tree` subfolders, number allocation, `bin/plan-number` | back end |
| Git date, lock file, `resync dirs`, M10 move | back end |
| `list-plans --all`, 🔑 column, `openlanes docs`, README | back end (CLI output is Ruby; `Reporter`, `Documentation`) |
| Web board link percent-encoding of the new name (`plans/index.rb:184`) | front end (`frontend-coder`): verify links with `━` and `❯` resolve; fix only if they do not |
| Control room 🔑 and any emoji column in `web/src` | front end: render 🔑, accept the new emoji set |

## Open questions

1. **Which date wins for an archived plan** when `state.json` `updated_at` and the git rename date disagree (research "not settled" 1)? Assumption in this spec: git rename date, because N5 says so, and `state.json` may not exist.
1. **Shallow clones:** does `git log --follow` survive them (research 2)? Assumption: fall back to `state.json` `updated_at`, then to today; unverified.
1. **Sort order of `list-plans --all`:** by number, with subfolders after open plans? N3 is silent (research 4). Assumption: number order within each group.
1. **Cross-host locks:** reported only, never cleared (follows from N4, not written there). Assumed.
1. **A folder renamed twice** and a spec edited after the move were not tested (research §3). Assumption: the `--follow --diff-filter=R` form returns the latest rename.
1. **Old-emoji mapping for `🅱️`:** research measured the bare `🅱` too; assumed both map to Product Block. Unconfirmed that no existing repo uses another variant.
1. **Reviving a plan:** N3 says moving back drops the date. Which command does this, a transition or a new `revive`? Not specified; assumed the state machine's rename out of a terminal state.
1. **Existing `new` status named in `STATUSES`:** the new emoji `⚪`, `⭐` etc. collide with nothing, but the Linear `mapping.rb` table is keyed by status key, not emoji; assumed unaffected, unchecked.
1. **M10 detail:** the exact heading text and where it is inserted when `## How to tell it's working?` already exists. Not covered by research; assumed append to the existing section.
1. **`created:` frontmatter key** (N3) for new specs: assumed in scope of `Creator` and `Brief`; not listed in the "What we are trying to achieve" text. Confirm.

## Risks to planning or execution

- **Ordering.** Migrating before the parser reads the new form renames everything wrongly. Work units must put the parser first and `resync dirs` migration last.
- **Live repositories.** `run` calls `resync dirs` before and after each round, so the first run after upgrade renames folders under any open worktree or PR branch. Branch names and `pull-requests.md` mention folder names (`publisher.rb:166`, `worktree.rb:81`).
- **Git history of other checkouts.** A rename in `main` conflicts with agents on old branches still using the old name.
- **Width drift.** Emoji width differs by terminal; specs can assert code points, not rendered cells.
- **Large blast radius.** Ten-odd call sites (research §1); a missed one fails only against a migrated repository, so specs need a migrated fixture, not just unit specs.
- **Interrupted research.** The first research round died; its numbers are from a single pass, with some paths untested (research §3).

## Conclusion

When this ships, new plans are created as `NNN.MM━━<emoji>━━❯<slug>` using six single-code-point emoji; the parser still reads every old form. Finished, deferred and discarded plans live in dated `archive/`, `deferred/` and `abandoned/` folders that `list-plans --all` includes and the default view hides, and plan numbers are never reused across them. A running agent leaves `locked-by.pid`, shown as 🔑, cleared by `resync dirs` when its process is gone on this host. The first `resync dirs` on any repository migrates names, locations and `how-to-verify:` keys with `git mv`, previewable with `-n`.


## Research

Method, all on 2026-10-13: `rg` over `lib/`, `bin/`, `web/src/`; `bundle exec rspec` (Ruby 4.0.6): 2214 examples, 0 failures; `unicode-display_width` 2.6.0 measured in the repo's bundle; a throwaway git repo for rename history. No sub-agent wave: one pass of greps answered every question, and a wave would repeat them. No web search: every external claim is about an installed gem or git, and both were measured locally.

### 1. Every place that builds or parses a folder name

Builds, all through `Plans.plan_dirname` (`lib/openlanes/plans/feature.rb:61`, `NNN.MM-<emoji> → <slug>`):

- `lib/openlanes/lifecycle/creator.rb:140`
- `lib/openlanes/lifecycle/adoption.rb:48`
- `lib/openlanes/evals/live.rb:86`
- `Feature#dirname_as`, `feature.rb:108`, used by `lifecycle/resync.rb:114` and `plans/subject.rb:120`

Parses:

- `Feature.parse`, `feature.rb:82-96`: strips `NNN.MM[-_]`, splits on `\s*→\s*|[-_]`, reads the status from the first segment. Callers: `plans/tree.rb:19`, `plans/subject.rb:127`, `plans/plan_state.rb:237`, `cli/create/create.rb:195,215,238`, `live/commands.rb:434`.
- `Ordinal.from_dirname`, `plans/ordinal.rb:43`: `/\A[\d.]+/`. Callers: `creator.rb:60`, `adoption.rb:138`, `vcs/publisher.rb:166`, `resync.rb:377`, `lib/openlanes.rb:133`.
- `bin/plan-number:115-134`: `find -maxdepth 1`, then a `[0-9]{3}` regex on branch names.

Read `feature.dirname` only, no parsing: `plans/index.rb:184` (web board links, percent-encoded), `linear/import.rb:147,263,274`, `linear/attribution.rb:150`, `vcs/publisher.rb:264,276`, `cli/worktree/worktree.rb:81` (string match).

- Web board (`web/src/board/model.ts:153`, `Board.tsx:16`) splits agent names on `-`, not folder names. Unaffected.
- Linear: `linear/issue.rb:37` keeps `linear.md` inside the folder, so a rename carries it along.

**Problem found:** `Feature.parse` does not read the new form. Measured with `Feature.parse("/x/" + name)`:

| Name | status | slug |
| --- | --- | --- |
| `028.00━━🟡━━❯state-tax-coverage` | `:new` | `028.00━━🟡━━❯state-tax-coverage` |
| `028.00━━⭐━━❯a-b` | `:new` | `028.00━━⭐━━❯a-b` |
| `018-⚪️--foo` (old) | `:new` | `foo` |

The `sub` on line 86 needs `[-_]` after the number, and `split` needs `━`/`❯` as separators. N5's migration must not run before `Feature.parse` reads the new form, or `resync dirs` would call every new name non-canonical.

### 2. How `Plans::Tree` walks the subfolders, and `list-plans --all`

- `Plans::Tree#directories` (`plans/tree.rb:68-76`) lists immediate children of `.plans` only. Nothing reads `archive/`, `deferred/` or `abandoned/`. Today such a folder lands in `Tree#skipped` (`tree.rb:30`), which no caller reads.
- `list-plans` has no `--all` option (`cli/list_plans/list_plans.rb:13`, `cli.rb:110`; `rg` for `--all` finds nothing). `--all` is new work.
- Numbers: N3 says numbers span the subfolders. Three places do not: `creator.rb:58` (`Dir.children(dir)`), `bin/plan-number:115` (`-maxdepth 1`), `lib/openlanes.rb:133` (`ls-tree -d .plans/`). A number in `archive/` can be reused today. No subfolder exists yet, so nothing collides yet.

### 3. Dates for archived plans from git

In a temp repo, `git mv` of a plan folder into `archive/`, then a commit:

- `git log --follow --diff-filter=R --format=%cI -- "archive/<folder>/spec.md"` returns the move commit.
- `git log -1 --format=%cI -- "archive/<folder>"` also returned the move commit, but only because nothing had changed since. A later edit to a file in the folder would make it the latest edit, not the move.

So use the `--follow --diff-filter=R` form on a file inside the folder. Not tested: a folder renamed twice, and a spec edited after the move. Not verified: shallow clones. This repo has no `.github/` workflow, so the CI depth is unknown.

### 4. Lock contents and the host check

- No lock exists today. `rg` for `locked`, `locked-by` finds nothing.
- Host precedent: `engine/dispatcher.rb:835` writes `run: { pid: Process.pid, host: Socket.gethostname }` into the plan's `state.json`.
- Liveness precedent: `Process.kill(0, pid)` at `plans/plan_state.rb:282` and `engine/state_file.rb:167`. The host check is needed before it: a PID from another machine means nothing.
- Ignore precedent: `engine/state_file.rb` (`ensure_ignored!`, referenced at `spec/openlanes/engine/state_file_spec.rb:126`) already adds git-ignore entries. `locked-by.pid` can reuse it.
- Existing claim check: `live/claims.rb:13` (`Claims`), injected into `engine/runner.rb:68` and consulted at `runner.rb:128`. A lock check could share it instead of adding a second one.

### Contradictions

- **Decisions file vs code.** `docs/decisions/decisions-on-plan-folder-naming.md` says "Not built yet". Production runs the old form: `feature.rb:61` emits `NNN.MM-<emoji> → <slug>`. Code wins for everything the decisions file does not yet describe.
- **N3 vs code on numbering.** N3 says numbers are allocated across all subfolders. Production numbers from the top level only (`creator.rb:58`, `bin/plan-number:115`). Code wins until the plan changes it.
- **N1 vs parser.** N1 says "the parser keeps reading the old form", and it also has to read the new one. It reads neither correctly for the new form (table above). Code wins; the plan must change the parser first.
- **This spec.** `spec.md` repeats four empty headings (`What we are trying to achieve` through `What research needs to settle`) after the filled-in copy, and ends with the harness note from an interrupted round. Left in place. spec-writer should read the first copy.

### What could not be settled

1. Which wins when a plan's `state.json` `updated_at` and its git date disagree, for plans whose `state.json` was never written by the harness. Needs an owner decision.
2. Whether `git log --follow` survives a shallow clone. Not verified; no CI workflow in this repo.
3. Lock liveness across hosts: `Process.kill(0)` is only meaningful on the same host, so a lock from another host can only be reported, never cleared. This follows from N4 but is not stated there.
4. Whether `list-plans` should show archived plans by date or by number. N3 says "open plans by default"; the sort order is not specified.

### Findings, Conclusion & References

**Findings**

- Folder-name code is spread over ten-odd call sites, all routed through `Plans.plan_dirname` and `Feature.parse`. Changing those two is the change; the other call sites follow.
- The new name form does not parse today (measured). The parser comes first in the plan.
- Subfolder numbering is missing in three places (`creator.rb:58`, `bin/plan-number:115`, `lib/openlanes.rb:133`), so N3's "a number is never reused" does not hold yet.
- `list-plans --all` does not exist.
- Emoji widths match N2 in the repo's `unicode-display_width` 2.6.0: `🅱️`, `☢️`, `🕰️` measure 1 cell, `⚪️`, `⭐️`, `⭕️` measure 2 (and the bare `🅱` 1). The new emoji `🛑 💤 ⏪ ⚪` each measure 2. `━` and `❯` measure 1.
- Locks: the host and liveness pieces exist in `state.json` and `Process.kill(0)`; the lock file does not.

**Conclusion**

spec-writer can write Goal, Non-Goals, scope and open questions from this chapter without asking. The first open question for the spec is item 1 above (which date wins for archived plans); the rest are implementation facts the plan can settle.

**References**

- `lib/openlanes/plans/feature.rb:61, 82-96, 108` (2026-10-13)
- `lib/openlanes/plans/tree.rb:19, 30, 68-76` (2026-10-13)
- `lib/openlanes/plans/ordinal.rb:43` (2026-10-13)
- `lib/openlanes/lifecycle/creator.rb:58-60, 140` (2026-10-13)
- `lib/openlanes/lifecycle/resync.rb:114, 195, 377` (2026-10-13)
- `lib/openlanes/lifecycle/adoption.rb:48, 138` (2026-10-13)
- `lib/openlanes.rb:133` (2026-10-13)
- `bin/plan-number:115-134` (2026-10-13)
- `lib/openlanes/engine/dispatcher.rb:835`, `engine/runner.rb:68, 128`, `live/claims.rb:13`, `engine/state_file.rb:113, 164-167` (2026-10-13)
- `lib/openlanes/plans/plan_state.rb:237, 282` (2026-10-13)
- `docs/decisions/decisions-on-plan-folder-naming.md` N1–N5 (2026-10-13)
- Measurements, 2026-10-13: `bundle exec rspec` → `2214 examples, 0 failures`; `Unicode::DisplayWidth` 2.6.0 widths as above; `Feature.parse` table above; temp-repo `git log --follow --diff-filter=R` output.
- External sources: none. Nothing paywalled or licensed was used.
