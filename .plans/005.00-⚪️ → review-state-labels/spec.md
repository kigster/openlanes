---
depends_on: []
---

# Review State Labels

## What we are trying to achieve

Every pull request a plan opens carries exactly one review-state label, which shows on GitHub where its review stands:

| Label | Colour | Meaning | Applied by |
| --- | --- | --- | --- |
| `ready-for-review` | `c2e0c6` | PR open, review not started | the harness, when it opens the PR |
| `review-in-progress` | `fff3b0` light yellow | hansolo is reviewing | hansolo, when it starts |
| `review-passed` | `0b6e2e` deep green | passed with non-critical findings still open | hansolo |
| `ready-to-merge` | `2ea043` bright green | passed with nothing open | hansolo |
| `review-rejected` | `b60205` deep red | changes needed | hansolo, or chewie-verifier (plan 014) |
| `ok-to-merge` | `1a7f37` | verified by running the app | chewie-verifier (plan 014) |

Missing labels are created before first use. A new label replaces the previous one. No verdict is given while CI is red; there is no label for approving over red CI. Labels are set through `openlanes review`, not raw `gh pr edit`.

In human merge mode the engine polls open PRs every 15 seconds: `review-rejected` with comments sends the plan to 🔴 and the comments to luke and rey; a merged PR makes the plan ✅; a PR closed unmerged makes it ❌. Needs you shows "waiting on you: PR #N".

Every spec says how to tell the work is done: `spec.md` gains `## How to tell it's working?`, which becomes `## How to test` in `plan.md` and in the PR body, replacing the `how-to-verify:` frontmatter key. The publisher refuses a PR without it.

## Why it matters

Today a reviewed PR looks the same on GitHub whether it is waiting, being reviewed, passed or rejected; its state lives only in `pull-requests.md` and `state.json`. Nothing stops an approval over red CI, and nothing tells a reviewer or a verifier how to check the result.

## What already exists

- Decisions M3, M4 and M10 in `docs/decisions/decisions-on-merge-modes-and-verification.md`. They replace L1 and L4 in `docs/decisions/decisions-on-web-ui-and-review-labels.md`; L3 (the `openlanes review` command) still stands.
- `agents/hansolo-reviewer.md`: currently `may: [gh pr review, gh pr comment]`.
- `lib/openlanes/execution/executor.rb`: `FORBIDDEN_COMMANDS` (includes `gh pr edit`, through which labels are set) and `UNGRANTABLE`.
- `lib/openlanes/vcs/publisher.rb`: opens the PR, the place to apply `ready-for-review` and to require `## How to test`.
- `lib/openlanes/vcs/github.rb`: the `gh` seam, which specs replace with a double.
- `lib/openlanes/plans/pull_requests.rb`: `STATES`, the review vocabulary as `pull-requests.md` records it.
- `lib/openlanes/lifecycle/completion.rb` and `lib/openlanes/plans/spec.rb`: today's `how-to-verify:` copy into `plan.md`.

## What research needs to settle

- Which `gh` calls create and swap labels idempotently, and how they fail on a fork or where the token cannot manage labels.
- What counts as red CI in `gh pr checks` (failing only, or cancelled too), and how pending checks wait (L5).
- Whether label states derive from `PullRequests::STATES` or the other way round, so the vocabulary is written once.
- Where the 15-second poll lives when `lanes start` is running and when only `lanes run` is.

## How to tell it's working?

- A PR opened by the harness carries `ready-for-review`; during review it shows `review-in-progress`; afterwards exactly one of `review-passed`, `ready-to-merge` or `review-rejected`.
- With CI red, `openlanes review` refuses any verdict except rejection.
- In human mode, adding `review-rejected` with a comment on GitHub moves the plan to 🔴 within about 15 seconds; merging it moves the plan to ✅.
- The publisher refuses to open a PR whose `plan.md` has no `## How to test`.
