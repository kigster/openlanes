# Plan: Auto Merge Passing PRs

## Backend

### U1 Merge gates (R5)

`Engine::Merging#merge` merges only a `ready-to-merge` PR (verifier's label, which displaces the passing review label) whose CI is green on its head, which GitHub reports neither `BEHIND`, `DIRTY` nor `UNKNOWN`, and whose `main` CI is green (`Vcs::GitHub#branch_checks`, read through `CiGate`). `DIRTY` leaves it `merge-manually` with a comment; `UNKNOWN` and non-green `main` wait.

### U2 Rebase other plan branches, queued per checkout

After an engine merge, every other non-terminal plan with an existing checkout is queued. `Dispatcher#settle_merges` drains the queue with `Merging#rebase_queued(busy: untouchable)`, so a checkout with an agent running stays queued and its `HEAD` is never moved under a boundary snapshot. `Vcs::Refresh` refuses uncommitted work; a conflict is aborted and left to that plan's next pre-run rebase; a rebased branch with an open PR is pushed through `Publisher#pushed!`.

## Frontend

None.

## Task completed when

- A passing, verified, green, clean PR is merged by the engine.
- A PR missing any one condition is not.
- After a merge, other open plan branches are rebased onto `main`, each queued until no agent is running in that checkout; a merge while another checkout is active leaves that checkout's `HEAD` alone and `Boundary` reports no violation, and uncommitted work is still protected.

## How to test

- A passing, verified, green, clean PR is merged by the engine.
- A PR missing any one condition is not.
- After a merge, other open plan branches are rebased onto `main`, each queued until no agent is running in that checkout; a merge while another checkout is active leaves that checkout's `HEAD` alone and `Boundary` reports no violation, and uncommitted work is still protected.

## Merge risk, PR #113

**Verdict:** manual

**Triggers:**

- The factory itself: `lib/openlanes/engine/merging.rb:155` (`rebase_queued`), `:168` (`rebase_checkout`) and `:338` (`queue_other_plans`) are merge rules that decide what merges and what gets rebased next. `lib/openlanes/engine/dispatcher.rb:1926` wires them into the dispatcher's settle loop.
- Destructive or external side effects: `merging.rb:184` and `:366` push rebased, rewritten branches of *other* plans through `Publisher#pushed!` (`git push` with a lease, `lib/openlanes/vcs/publisher.rb:395`). A revert does not undo a rewritten remote branch.

**Signals:**

- Hard-to-test behavior: the rebase queue depends on concurrency (busy checkouts, `untouchable`, boundary snapshots) and on GitHub `mergeStateStatus` timing (`UNKNOWN`, `merging.rb:320`). The specs use `fake_gh` (`spec/support/fake_gh/fake_gh.rb:105`), not real GitHub.
- No off switch for the rebase: once `merge.by: auto` merges anything, every other non-terminal plan with a checkout is queued for rebase and push. No flag exists for the rebase on its own.
- Thin review: `gh pr view 113` lists no reviews. The only sign-off is verifier's `ready-to-merge` label (commit `760e6118`).
- Shared code: `Vcs::GitHub#branch_checks` (`lib/openlanes/vcs/github.rb:362`) now gates every merge on `main` CI. If it misreads CircleCI statuses, every merge is held, or a red `main` passes.

**Unplanned files:** none. `github.rb` (`branch_checks`) and `fake_gh.rb` serve U1. `dispatcher.rb`, `dispatcher_merging_spec.rb:46` (a stub added for `rebase_queued`, not a loosened assertion) and `merging*.rb` serve U2. `state.json` is the harness's own.

**Rollback:** `git revert -m 1 cdb57836` restores the previous merge behavior in the next gem release. Branches that were already rebased and force-pushed stay rewritten; restore those from the reflog of each worktree.

**For the human:**

- PR #113 is already `MERGED` (by kigster, 2026-10-22T17:41:08Z, merge commit `cdb57836`), so this verdict only records the risk.
- Check `merging.rb:155-190`: a rebase plus `pushed!` on another plan's branch must never run while that plan's agent is active, and must refuse when the tree has uncommitted work.
- Check `github.rb:362` against real CircleCI output on `main` (statuses, no check runs) before turning on `merge.by: auto`.
