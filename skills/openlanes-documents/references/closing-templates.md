# Closing documents

Each of these files is what one off-path state requires (`openlanes docs` lists which). Write the file, then `openlanes resync dirs` moves the folder; rename by hand only if resync names a different state than you meant.

## discarded.md — ❌ Discarded

Dropped for good; terminal. Say why, so nobody re-proposes it blind.

```markdown
# Rate Feed Sync — Discarded

**Decided:** 2026-10-13 by the head of product
**Why:** the vendor withdrew the feed; filed returns carry the rates we need.
**What would change our minds:** a regulator requiring live rates.
```

## delayed.md — ☢️ Deferred

The work could proceed and we chose not to yet. openlanes refuses the state unless the file names a **trigger** (it looks for the words trigger, revisit, when, until or once).

```markdown
# Rate Feed Sync — Deferred

**Deferred:** 2026-10-13 by the CTO
**Why now is wrong:** the ledger refactor in 021 rewrites the tables this touches.
**Trigger:** revisit once plan 021 is merged.
```

## rewrite.md — 💩 Scrapped by Review

Written by `hansolo-reviewer` when the work is missing, broken, untested, off-spec, or still failing after two rejections. The plan survives; the pull requests do not. No agent handles 💩: a human reads this and decides whether to re-plan, rewrite the spec, or discard.

```markdown
# Rate Feed Sync — Rewrite

**Reviewed:** 2026-10-13, PR #41
**Why it was scrapped:** the sync never writes to the rates table; the spec's verification command fails.
**What the next attempt must do differently:** …
```

## deployed.md — 😎 Deployed

```markdown
# Rate Feed Sync — Deployed

**Release:** v1.8.0
**Date:** 2026-10-14
**SHA:** 3f2c9ab
```

## rollback.md — 😱 Rolled Back

```markdown
# Rate Feed Sync — Rolled Back

**Rolled back:** 2026-10-15, v1.8.0 → v1.7.3
**What broke:** the nightly sync locked the rates table for 40 minutes.
**What has to change before it ships again:** …
```
