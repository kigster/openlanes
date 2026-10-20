# Decisions on merge risk assessment

Decided 2026-10-19, with Konstantin, when `palpatine-planner` became `luthen-rael-planner` and `palpatine-risk-assessor` was added as the last agent before a merge.

## P1. 🏁 Completed is a plan state, and palpatine handles it

- `ready-to-merge` is a pull request's state, not a plan's. Once every open pull request of a plan carries it, the plan moves from 🧪 Verifying to 🏁 Completed.
- `palpatine-risk-assessor` handles 🏁 and nothing else. It gives each pull request a verdict, `auto` or `manual`.
- Completed is not done. A 🏁 plan still has at least one open pull request. It sits in the building family, because the folder's contents alone cannot tell 🏁 from 🧪.

## P2. A pull request has a state machine of its own

- A plan can have several pull requests, so the pull request carries its own lifecycle: `Plans::PullRequestMachine`.
- The states are `open`, then `ready_to_merge` (labelled `ready-to-merge`), then `complete` (palpatine's verdict has been acted on), then `merged`. `closed` is the other way out.
- A complete pull request carries its verdict as a label:
  - `auto-merged` (#953384): the engine merged it.
  - `merge-manually` (#0e8a16): left open for a person to merge.
- The state is read from the pull request's GitHub labels and its row in `pull-requests.md`. Nothing stores it a second time.

## P3. ✅ means every pull request is merged

- A plan is ✅ only once every pull request has merged, automatically or by hand. Then `resync dirs` moves it into `archive/`.
- While any pull request is `merge-manually`, the plan stays at 🏁, settled: no agent touches it again. When a person merges on GitHub, the existing merge detection (`PrOutcomes#merged`) moves it to ✅ once nothing is left open.

## P4. `merge.by` gates the merge

- palpatine runs at 🏁 under both `merge.by` modes.
- The engine merges an `auto` pull request only under `merge.by: auto`. Under `merge.by: human` (the default) every pull request is labelled `merge-manually`, whatever the verdict was.
- A run that ends without palpatine's verdict (killed, or a signature that cannot be read) counts as `manual`. The cost is lopsided: a wrong `manual` costs a person ten minutes.
- The engine merges with `gh pr merge --merge`, which matches the repository's merge commits. `gh pr merge` stays ungrantable to agents (M2).

## P5. Sibling pull requests merge one at a time, rebased between merges

- The engine merges a plan's `auto` pull requests in the order `pull-requests.md` lists them, one at a time.
- After each merge, every other open pull request of the same plan is rebased onto `main`. A conflict sends the plan to 🔴, with the conflict mailed to luke and rey.
- Rebasing the branches of *other* plans after a merge stays in plan 033's scope.
- A rebased sibling keeps `ready-to-merge` and merges only once CI is green on its new head. Zero checks within five minutes of the rebase read as "CI has not registered yet", not as green. Red CI after a rebase also sends the plan to 🔴.
- The plan's own branch is rebased in its worktree, when one exists, and pushed with the lease; any other branch is rebased by GitHub (`gh pr update-branch --rebase`). A merge GitHub refuses leaves the pull request `merge-manually`.
- A plan reaches 🏁 only once every open pull request carries `ready-to-merge`. Verification labels the plan's last open pull request, so a plan with a second one (adopted, or opened by a person) waits at 🧪 until a person labels it.
