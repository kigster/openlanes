# Decisions on which plan writes need the main checkout

Date: 2026-10-20. Asked by kig.

## Why

Some writes to `.plans` must happen one at a time, in one place. Done in two worktrees at once, they collide: two checkouts mint the same plan number, or write `depends_on:` edges against two different views of which plans exist. Other writes, such as an agent editing its own plan's `plan.md`, cannot collide that way and need no such rule.

This extends the 2026-10-17 rule in `lib/openlanes/lifecycle/allocator.rb`, which kept plan creation out of linked worktrees but allowed it on any branch of the primary checkout.

## Decisions

### D1. Serial plan writes run only in the primary checkout, on its default branch

"The main repo" means the primary checkout (`git rev-parse --git-dir` equals `--git-common-dir`) with its default branch checked out. The default branch is origin's `HEAD`, else `main`. A linked worktree, another branch, or a detached `HEAD` is refused with a message naming why. Outside a git repository nothing is refused.

### D2. The rule covers three writes, and only those

- **A new plan folder**: `openlanes create`, a plan created on the control room page, and `resync prs` adopting an orphan pull request.
- **A new plan's opening `spec.md`**: `Lifecycle::Brief#write_scaffold!`.
- **`depends_on:`** in any `spec.md`. Nothing writes it yet; the `ewoki-linker` and `link` command of plan 008.01 are the first writers and must call `Lifecycle::Allocator#refuse!` before writing.

### D3. Everything else in a plan folder stays writable from a worktree

`plan.md`, `blocked.md`, `state.json`, edits to an existing `spec.md` other than `depends_on:`, and folder renames (`resync dirs`, state transitions) are written from worktrees as before. That is how agents work: each one edits its own plan inside its own checkout.

### D4. One check, in one place

`Lifecycle::Allocator#refusal` is the only definition of the rule. Every guarded write asks it, so the guards cannot disagree about what "the main repo" means.
