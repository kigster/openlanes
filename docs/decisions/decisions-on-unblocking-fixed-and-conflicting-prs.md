# Decisions on unblocking fixed and conflicting pull requests

Decided 2026-10-24, with Konstantin, after rejected pull requests kept `review-rejected` once their fixes landed, and pull requests waiting to merge went stale against `main` after another one merged.

## Background: why `review-rejected` stays

- When the publisher pushes a rebuild, it does swap the labels. On #93, the push at 10:07:03 was followed by `review-rejected` going and `ready-for-review` arriving within four seconds.
- The label stays when the fix reaches the pull request some other way. Again on #93, the rejection came at 10:09, and `abe2979` was pushed at 15:45 from a worktree openlanes did not run. Nothing looked at the label again. #83 and #44 show the same pattern.
- So the publisher is not the only place that has to look. Whatever pushed, the harness has to notice a push that came after the rejection.

## U1. A fixed pull request is labelled `review-addressed`

- New review label `review-addressed`, after `review-rejected` and `review-vulnerability`: rejected → addressed → in progress.
- The harness applies it, never an agent: agents cannot push or edit labels (`UNGRANTABLE`, the autonomy boundary).
- The publisher applies it in place of `ready-for-review` when it pushes to a pull request that is already open. A first submission still gets `ready-for-review`.
- Each merge poll, the engine also asks GitHub about every open pull request labelled `review-rejected`. When the head commit's committer date is later than the latest `review-rejected` label event, the fix has been pushed, whoever pushed it, and the labels are swapped to `review-addressed`. This needs no stored state, so a fix pushed while the engine was down is noticed when it next starts.
- Nothing reads `ready-for-review` to schedule a review: hansolo is dispatched by the plan's state (🟢). So `review-addressed` needs no change to scheduling.

## U2. The conflict sweep checks pull requests waiting to merge

- Only open pull requests labelled `ready-to-merge`, `merge-manually`, `review-approved` or `review-ok-not-perfect`. These have passed review and nobody is working on them, so nothing else will notice them going stale.
- Pull requests still in review or being rebuilt are left alone: their next round rebases them before the agent starts.
- Only pull requests recorded in a plan's `pull-requests.md`: resolving a conflict needs the plan's worktree and branch. A plan an agent is working in is skipped until that agent is done.
- A pull request still carrying `conflicts` stays in the sweep whatever its review label, so a failed resolution is tried again.

## U3. A resolved conflict keeps the review verdict

- A conflicting pull request gets `conflicts` beside its review label, and is handed to bb8-resolver. The harness rebases the plan's branch onto `main` in its worktree, and bb8 resolves what stops, up its model ladder (`Engine::Rebase`, D10).
- While `conflicts` is on a pull request, the merge step waits rather than leaving it for a person. It used to label a `DIRTY` or `BEHIND` pull request `merge-manually`.
- The harness pushes the resolution, removes `conflicts` and adds `conflicts-resolved`. The review label stays as it was: `ready-to-merge`, `merge-manually`, `review-approved` or `review-ok-not-perfect`.
- It merges only once CI is green on the new head. The merge step already waits for that.

## U4. The sweep runs whenever `main` moves

- The engine watches `origin/main`. When its head changes, whether the engine merged, a person merged on GitHub, or anyone pushed, the waiting pull requests are checked again.
- GitHub answers `UNKNOWN` for a while after `main` moves. Such a pull request is asked again on the next poll until GitHub gives a definite answer.
- `BEHIND` without a conflict needs no agent: GitHub updates the branch (`gh pr update-branch`), and the merge waits for CI on the new head.
- If bb8-resolver gives up, D10 holds: a conflict never becomes a question. `conflicts` stays on the pull request, and each later sweep tries one step up bb8's model ladder. Once the ladder is spent, the next move of `main` starts it again from the bottom.

## Implementation

- `Plans::ReviewLabel::ADDRESSED`, `WAITING`, `CONFLICTS`, `CONFLICTS_RESOLVED`; the `address` event on `Plans::PullRequestMachine`.
- `Engine::Upkeep`, one class per duty, behind `Upkeep::Keeper`, the only object the dispatcher talks to:
  - `Addressing` (U1) reads two new `Vcs::GitHub` calls, `labelled_at` and `head_committed_at`.
  - `Sweep` (U2, U4) reads `branch_head` and each pull request, classifies it with `Verdict` (pure, no I/O), and acts through `Actions` (every label, comment and branch update it writes).
  - `Owed` is the sweep's only memory: who still owes an answer, and the once-per-head-of-`main` push gate.
  - `Resolution` (U3) decides what follows a rebase. It pushes through a callable, so it knows neither the publisher nor the runner.
- `Dispatcher#upkeep_pull_requests` runs the keeper once per merge poll. The dispatcher keeps only the scheduling: slots, locks, and the bb8-resolver rebase job (`resolve_conflict`).
- `Engine::Merging` waits on `BEHIND` and `DIRTY` instead of labelling them `merge-manually`.
- The sweep needs a publisher and worktree isolation, so it is off in dry runs and shared-tree runs.
