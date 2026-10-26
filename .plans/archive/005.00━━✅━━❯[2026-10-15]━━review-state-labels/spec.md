---
depends_on: []
---

# Review State Labels

## What we are trying to achieve

Every pull request a plan opens carries exactly one review-state label, which shows on GitHub where its review stands:

| Label | Colour | Meaning | Applied by |
| --- | --- | --- | --- |
| `ready-for-review` | `c2e0c6` | PR open, review not started | the harness, when it opens the PR |
| `review-in-progress` | `fff3b0` light yellow | staff-reviewer is reviewing | staff-reviewer, when it starts |
| `review-passed` | `0b6e2e` deep green | passed with non-critical findings still open | staff-reviewer |
| `ready-to-merge` | `2ea043` bright green | passed with nothing open | staff-reviewer |
| `review-rejected` | `b60205` deep red | changes needed | staff-reviewer, or verifier (plan 014) |
| `ok-to-merge` | `1a7f37` | verified by running the app | verifier (plan 014) |

Missing labels are created before first use. A new label replaces the previous one. No passing verdict is given while CI is red (a rejection is); there is no label for approving over red CI. Labels are set through `openlanes review`, not raw `gh pr edit`.

In human merge mode the engine polls every PR it opened, every 15 seconds, until it is merged or closed: `review-rejected` with comments sends the plan to 🔴 and the comments to backend-coder and frontend-coder; a merged PR makes the plan ✅; a PR closed unmerged makes it ❌. Needs you shows "waiting on you: PR #N".

Every spec says how to tell the work is done: `spec.md` gains `## How to tell it's working?`, which becomes `## How to test` in `plan.md` and in the PR body, replacing the `how-to-verify:` frontmatter key. The publisher refuses a PR without it.

## Why it matters

Today a reviewed PR looks the same on GitHub whether it is waiting, being reviewed, passed or rejected; its state lives only in `pull-requests.md` and `state.json`. Nothing stops an approval over red CI, and nothing tells a reviewer or a verifier how to check the result.

## What already exists

- Decisions M3, M4 and M10 in `docs/decisions/decisions-on-merge-modes-and-verification.md`. They replace L1 and L4 in `docs/decisions/decisions-on-web-ui-and-review-labels.md`; L3 (the `openlanes review` command) still stands.
- `agents/staff-reviewer.md`: currently `may: [gh pr review, gh pr comment]`.
- `lib/openlanes/execution/executor.rb`: `FORBIDDEN_COMMANDS` (includes `gh pr edit`, through which labels are set) and `UNGRANTABLE`.
- `lib/openlanes/vcs/publisher.rb`: opens the PR, the place to apply `ready-for-review` and to require `## How to test`.
- `lib/openlanes/vcs/github.rb`: the `gh` seam, which specs replace with a double.
- `lib/openlanes/plans/pull_requests.rb`: `STATES`, the pull request lifecycle (`Closed`, `Merged`, `WIP`, `Open`) as `pull-requests.md` records it. It holds no review words (research, question 3); the review labels need a constant of their own.
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


## Research

Answers come from this checkout (branch `kig/005.00-review-state-labels`, read 2026-10-13) and from `gh` 2.102.0 installed here. No live GitHub call was made, so every claim about GitHub's server behaviour is marked unverified.

### Questions answered

**1. Which `gh` calls create and swap labels idempotently, and how they fail.**

- Create: `gh label create <name> --color <hex> --description <text>`. Without `--force` it fails when the label exists. `--force` would update an existing label's colour, which L1 forbids ("a label that already exists is left alone, colour included", `docs/decisions/decisions-on-web-ui-and-review-labels.md:325`). So use the non-forcing create and treat "already exists" as success, or list first with `gh label list --json name`. Sources: `gh label create --help` (local); a search snippet from [GitHub labels reference, git.cynarski.dev](https://git.cynarski.dev/Awesome/awesome-copilot/raw/commit/16b290efdfe99744c52ca8b5960e5bfb309cdbec/skills/github-issues/references/labels.md), retrieved 2026-10-13, not fetched in full.
- Swap: one call, `gh pr edit <n> --remove-label <old> --add-label <new>`. `--add-label` takes label names ([gh pr edit manual, snippet](https://manpages.opensuse.org/Leap-16.0/gh/gh-pr-edit.1.en.html), retrieved 2026-10-13). Removing a label the PR does not carry: **unverified**.
- Seam: `Vcs::GitHub` is where this belongs. `retitle` (`lib/openlanes/vcs/github.rb:159`) shows the pattern: run `gh pr edit`, rescue `TTY::Command::ExitError`, raise `Error` with the first stderr line.
- Agents may not call it. `gh pr edit` is in `FORBIDDEN_COMMANDS` (`lib/openlanes/execution/executor.rb:324-329`), so only the `openlanes review` path may run it.
- Fork PR, or a token without write access on the base repo: **unverified**. Expect a permission error from `gh pr edit`. The label call must surface that error, not swallow it. A live check needs a throwaway repo and an outward-facing write, so it was not run.
- Repository selection: `gh` uses the checkout's repository. Passing `-R owner/repo`, taken from the PR URL, avoids writing to the wrong remote when a worktree has several.

**2. What counts as red CI in `gh pr checks`, and how pending waits.**

- `gh pr checks <n> --json name,state,bucket` returns `bucket` as `pass`, `fail`, `pending`, `skipping` or `cancel` (`gh pr checks --help`, local).
- Exit codes: `8` means checks pending. Generic failure is `1`, auth is `4` (`gh help exit-codes`, local). Parse the JSON `bucket` field for pass and fail, not the exit code: the help text does not say which exit code a failed check gives.
- Recommendation: red = any `fail` or `cancel`; pending = wait (L5, `decisions-on-web-ui-and-review-labels.md:339`); `skipping` = neutral. Use every check, not `--required`, because L4 says "any check is failing".
- Nothing reads CI today. `rg` for `checks` in `lib/openlanes/vcs` and `lib/openlanes/engine` finds nothing, so this is all new code.

**3. Whether label states derive from `PullRequests::STATES`, or the reverse.**

- Neither, because they are different vocabularies. `PullRequests::STATES` (`lib/openlanes/plans/pull_requests.rb:13`) holds the pull request lifecycle: `Closed 🔴`, `Merged 🟣`, `WIP 🟡`, `Open 🟡`. It has no review words. The spec's claim that it is "the review vocabulary" is wrong.
- Recommendation: one constant for the six review labels (name, colour, meaning), read by `openlanes review`, `Vcs::Publisher` (`lib/openlanes/vcs/publisher.rb:84`) and the generated docs. Keep `PullRequests::STATES` as it is. `pull-requests.md` is parsed against it, and mixing the two would make `normalize` read a review label as a lifecycle state.
- The M3 table (`docs/decisions/decisions-on-merge-modes-and-verification.md:25-38`) and this spec's table are hand-written copies of that constant. `CLAUDE.md` forbids the duplication, so the constant should win, and the spec table should be generated or checked by a spec.

**4. Where the 15-second poll lives under `openlanes start` and under `openlanes run`.**

- Today nothing polls GitHub. `Dispatcher#poll` (`lib/openlanes/engine/dispatcher.rb:879`) reads the ledgers of running agents only. M4's human-mode poll is not built.
- Tick: one per second (`lib/openlanes/engine/dispatcher.rb:164`). `RESCAN = 5` (`dispatcher.rb:86`) only rescans the tree.
- `openlanes start` is `run` with `stay: true` (`lib/openlanes/cli/start/start.rb:53`, `lib/openlanes/cli/run/run.rb:196-204`). `Dispatcher#done?` (`dispatcher.rb:185`) never ends a staying run, so a poll in the tick is safe there.
- Plain `openlanes run` ends at the first fixed point when there is no control room, or with `--until-settled` (`run.rb:186-190`). A poll that waits for a human merge would hang a headless run, so it either stops there or holds the run open. That is a product choice, open question 4.
- Implementation: a 15-second timer checked from the tick, not a tick count, so a slow tick does not stretch the interval. Each poll makes one `Vcs::GitHub#pulls` call (`lib/openlanes/vcs/github.rb:28`), which lists every pull request at once, rather than one `gh pr view` per pull request.

### Contradictions: draft, earlier plans, config, code

Production runs the code column in each row.

| # | Draft or decision says | Code and config say |
| --- | --- | --- |
| C1 | `pull_requests.rb` holds the review vocabulary (spec, "What already exists") | It holds the PR lifecycle, `pull_requests.rb:13` |
| C2 | staff-reviewer sets labels through `openlanes review`; L3 removes `gh pr review` from its `may:` | `agents/staff-reviewer.md:13` still has `may: [gh pr review, gh pr comment]`. Neither is in `UNGRANTABLE` (`executor.rb:338`), so staff-reviewer can call both today |
| C3 | `openlanes review` is the label path (M3, L3) | No `review` command is registered (`lib/openlanes/cli.rb:105-150`). It is to be built |
| C4 | M10: `## How to tell it's working?` replaces the `how-to-verify:` key, and becomes `## How to test` | Code still reads the key (`lib/openlanes/plans/spec.rb:107`) and the heading `## How to verify` (`lib/openlanes/lifecycle/completion.rb:15`). Plan 007 migrates this, per `decisions-on-merge-modes-and-verification.md:104` |
| C5 | Spec table names `verifier` as the applier of `ok-to-merge` | No `verifier` in `agents/` (nine files). It belongs to plan 014 |
| C6 | M4: engine polls every PR in human mode | No such poll exists (question 4). Not built, so no code conflict |
| C7 | L1 colours (`b7ebc6`, `d73a4a`, …) | Superseded by M3 (`c2e0c6`, `b60205`, …). This spec uses M3, which is right per M3's header |

### Could not settle

1. Whether `gh pr edit --add-label` on a missing label, or on a fork PR without write access, fails, and with what message. Needs one live check on a throwaway repo, which is outward-facing and was not run.
2. How GitHub maps `action_required`, `startup_failure` and `timed_out` runs to the `bucket` field. Not verified.
3. Whether a pull request with zero checks counts as green, or as "no CI, no verdict". The spec is silent.
4. Whether plain `openlanes run` should exit at the first fixed point while PRs are still open, or hold the run until each merges. Product tradeoff. Options: (a) exit, and let a later `openlanes start` pick it up, with a log line naming the unpolled PRs; (b) block. Recommendation: (a).
5. Whether a failure to apply `ready-for-review` should stop the PR from opening. Recommendation: no. The PR is the work. Record the failure in the attempt note, as `publish_for_review` already does for refusals (`lib/openlanes/engine/dispatcher.rb:1195-1210`).

### Findings, Conclusion & References

Conclusion:

- The label vocabulary should live once, in code. `PullRequests::STATES` stays separate.
- Label writes go through `Vcs::GitHub` and `openlanes review`, never through an agent. `gh pr edit` stays forbidden to agents.
- Red CI = `fail` or `cancel` in the `bucket` field. Pending waits. Parse JSON, not exit codes.
- Nothing polls GitHub today. A 15-second poll fits in the dispatcher tick under `openlanes start`. Under plain `run` it is a product choice.
- Before this plan is built, C2 (`gh pr review` in staff-reviewer's `may:`) and C4 (the old `how-to-verify` key) must change in scope, since both contradict the decisions this plan implements.

References:

- Repository, read in this checkout: `lib/openlanes/plans/pull_requests.rb:13`, `lib/openlanes/vcs/github.rb:28,143,159`, `lib/openlanes/vcs/publisher.rb:84,240`, `lib/openlanes/execution/executor.rb:324-338`, `lib/openlanes/engine/dispatcher.rb:86,164,185,879,1195-1210`, `lib/openlanes/cli/start/start.rb:53`, `lib/openlanes/cli/run/run.rb:186-204`, `lib/openlanes/cli.rb:105-150`, `lib/openlanes/plans/spec.rb:107`, `lib/openlanes/lifecycle/completion.rb:15`, `agents/staff-reviewer.md:13`.
- Decisions: `docs/decisions/decisions-on-merge-modes-and-verification.md` (M3, M4, M10); `docs/decisions/decisions-on-web-ui-and-review-labels.md` (L1, L3, L4, L5).
- Local tools: `gh` 2.102.0: `gh pr checks --help`, `gh label create --help`, `gh pr edit --help`, `gh help exit-codes`.
- Web, retrieved 2026-10-13, from search snippets and not fetched in full: [gh pr edit manual](https://manpages.opensuse.org/Leap-16.0/gh/gh-pr-edit.1.en.html); [GitHub labels reference](https://git.cynarski.dev/Awesome/awesome-copilot/raw/commit/16b290efdfe99744c52ca8b5960e5bfb309cdbec/skills/github-issues/references/labels.md).

## Framing

Two ways to state the problem:

1. **Labels as a display.** A PR's review state is only visible on GitHub; add labels and a poll so the display matches the ledger.
1. **Labels as the verdict channel.** The label is the one place a verdict is written and read: `openlanes review` writes it behind a CI gate, the engine reads it back to drive the plan.

Chosen: 2. In human merge mode the human's only lever is the label, so it must be a gate the engine acts on (research, question 4, and M4), and a gate needs one writer (`openlanes review`) that refuses a verdict over red CI.

## Goal

Every PR a plan opens carries exactly one of six review-state labels, written only through `openlanes review` (never by an agent's raw `gh pr edit`). A passing verdict is refused while CI is red. In human merge mode the engine polls open PRs and moves the plan to 🔴, ✅ or ❌ from what GitHub shows. Every spec says how to tell the work is done, and the publisher refuses a PR without it.

## Non-Goals

- Verifying the app by running it, and applying `ok-to-merge`. That is `verifier`, plan 014 (research C5). This plan only defines the label.
- Merging. Merging stays ungrantable to agents (`UNGRANTABLE`, `executor.rb:338`).
- Changing `PullRequests::STATES` or the `pull-requests.md` format (research, question 3).
- Labelling PRs not opened by the harness, or PRs opened before this ships.
- A web UI for labels. `docs/decisions/decisions-on-web-ui-and-review-labels.md` L1 colours are superseded by M3 (research C7) and are not reimplemented.
- Recolouring a label that already exists (L1, `decisions-on-web-ui-and-review-labels.md:325`).

## In scope

1. A single constant lists the six labels with name, colour, meaning; `openlanes review`, `Vcs::Publisher` and generated docs read it. Check: a spec asserts the six names and colours match M3 (`decisions-on-merge-modes-and-verification.md:25-38`), and `rg` finds each name literal in one file only.
1. `Vcs::GitHub` gains label operations: ensure-exists (non-forcing create, "already exists" is success, existing colour untouched) and swap (`gh pr edit <n> --remove-label <old> --add-label <new>`, `-R` from the PR URL). Failures raise `Error` with the first stderr line, as `retitle` does (`github.rb:159`). Check: spec with a `GitHub` double covers create-when-missing, left-alone-when-present, swap, and error surfacing.
1. A new `openlanes review` command, registered in `cli.rb`, sets a verdict label on a PR with replace-not-add semantics, supports `-n`/`--dry-run`. Check: spec shows one label left after each transition, and dry-run changes nothing.
1. CI gate: red = any check with bucket `fail` or `cancel` from `gh pr checks <n> --json name,state,bucket`; `skipping` is neutral; `pending` waits (L5). Only `review-rejected` is accepted while red. Check: spec with check fixtures for pass, fail, cancel, pending, skipping.
1. `Vcs::Publisher` applies `ready-for-review` when it opens a PR; a label failure is recorded in the attempt note and does not stop the PR (open question 4). Check: spec with a failing label double still yields an open PR and a note.
1. staff-reviewer applies `review-in-progress` at start and its verdict at end, through `openlanes review`. `agents/staff-reviewer.md` `may:` drops `gh pr review` (research C2). Check: the frontmatter spec asserts the new `may:`; `gh pr edit` stays in `FORBIDDEN_COMMANDS`.
1. Human-mode poll: a 15-second timer, checked from the dispatcher tick (not a tick count), makes one `Vcs::GitHub#pulls` call. `review-rejected` with comments → 🔴 and the comments go to backend-coder and frontend-coder; merged → ✅; closed unmerged → ❌. Under `openlanes start` only (open question 1). Check: dispatcher spec with an injected clock and `GitHub` double for each of the three outcomes.
1. "Needs you" shows `waiting on you: PR #N` for open PRs in human mode. Check: reporter spec.
1. `## How to tell it's working?` in `spec.md` becomes `## How to test` in `plan.md` and the PR body, replacing the `how-to-verify:` key; the publisher refuses a PR without it. Check: specs on `completion.rb` and `publisher.rb`.
1. `openlanes docs` regenerates the label table from the constant. Check: docs spec compares output to the constant.

## Out of scope

- `ok-to-merge` application: needs the verifier, plan 014.
- Auto-merge mode behaviour: M4 defines only the human-mode poll.
- Backfilling old plans' `how-to-verify:` keys: migration is plan 007 (`decisions-on-merge-modes-and-verification.md:104`); this plan must tolerate the old key until 007 lands (open question 3).
- Live fork/permission testing against GitHub: an outward-facing write needing a throwaway repo.

## Back end / front end

| Item | Half | Builder |
| --- | --- | --- |
| 1 constant, 2 `GitHub` ops, 3 `review` command logic, 4 CI gate, 5 publisher, 6 staff-reviewer definition, 7 poll, 9 how-to-test, 10 docs | back end | `backend-coder` |
| 8 Needs-you line; `review` command output and help text | front end (terminal presentation) | `frontend-coder` |

There is no web front end in this plan. `frontend-coder` owns terminal output only; `backend-coder` exposes the data it renders.

## Open questions

1. Plain `openlanes run` with PRs still open: exit at the first fixed point and log the unpolled PRs (recommended, research could-not-settle 4), or block until merge? This spec assumes exit, and builds the poll for `start` only. Needs a product decision.
1. A PR with zero checks: green or "no CI, no verdict"? The draft is silent (research, could-not-settle 3). Assumed green with a warning.
1. Until plan 007 lands, should `completion.rb` accept both `how-to-verify:` and `## How to tell it's working?`? Assumed yes, new heading wins.
1. If `ready-for-review` fails to apply, the PR still opens (research, could-not-settle 5). Assumed, as recommended.
1. How GitHub maps `action_required`, `startup_failure`, `timed_out` into `bucket` (research, could-not-settle 2). Unverified; the gate treats unknown buckets as red.
1. `--remove-label` for a label the PR lacks, and `--add-label` on a missing label or fork PR: failure mode unverified (research, could-not-settle 1). The swap ensures the label first and tolerates a failed remove.
1. Stale `review-in-progress` when staff-reviewer is killed mid-review: not covered by the draft; assumed the next round's swap replaces it.

## Risks to planning or execution

- Plan 014 needs the label constant and `openlanes review`, so their names are an interface; changing them late breaks 014.
- Plan 007 touches the same `how-to-verify` reads (`spec.rb:107`, `completion.rb:15`); merge-order conflict.
- The poll is a new GitHub reader in the tick; a slow `gh` call stalls the one-second tick (`dispatcher.rb:164`) unless it runs off the tick.
- `gh pr checks` is one call per PR in the gate and is not batched.
- `dispatcher.rb` is large and edited by other plans, so the poll hunk may conflict.
- All GitHub server behaviour is unverified (research); the first live run is the real test.

## Conclusion

When this ships, every harness-opened PR wears exactly one review label, set by one constant and one command, and a passing verdict cannot be recorded over red CI. Under `openlanes start` in human mode the engine reads GitHub every 15 seconds and moves plans to 🔴, ✅ or ❌. Every plan carries a `## How to test` that reaches `plan.md` and the PR body, and the publisher refuses a PR without one.
