# Plan: Auto Merge Passing PRs

## Backend

### U1 Merge gates (R5)

`Engine::Merging#merge` merges only a `ready-to-merge` PR (chewie's label, which displaces the passing review label) whose CI is green on its head, which GitHub reports neither `BEHIND`, `DIRTY` nor `UNKNOWN`, and whose `main` CI is green (`Vcs::GitHub#branch_checks`, read through `CiGate`). `DIRTY` leaves it `merge-manually` with a comment; `UNKNOWN` and non-green `main` wait.

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
