# Decisions on three reviewers, review labels and auto-merge

Decided 2026-10-16 by the owner (kig). Grilling session, one question at a time. Measured against M0 in [decisions-on-agent-memory-and-sessions.md](decisions-on-agent-memory-and-sessions.md): a person intervenes as rarely as possible.

Amends M3 and M5 in [decisions-on-merge-modes-and-verification.md](decisions-on-merge-modes-and-verification.md).

## Reviewers

### R1. Three reviewers, each from its own angle

Three reviewers start at the same time on a PR, each with a sub-agent concurrency of 1. Their instructions share one part (how to review, the comment format) and differ in what they look for.

| Agent | Manner | Default model | Looks for |
| --- | --- | --- | --- |
| `hansolo-reviewer` | adversarial, thorough, a nit-picking Staff Engineer | Opus 5.5, the most capable: review matters most | serious logic bugs, readability, runtime errors, memory leaks, N+1 queries; reimplementing code that already exists, or what a hardened popular library already does; assumptions in the code that may not hold at runtime |
| `darth-reviewer` | friendly | a fast cheap model: Haiku. Gemini's fastest Flash is optional, used only if an adapter can reach it | core logic bugs, unchecked nil/null access, database safety and integrity, load on infrastructure, scalability, fault tolerance |
| `vader-security-reviewer` | friendly, security only | a medium model: Sonnet | anything in the PR's code that can be exploited: SQL injection, CSRF, spoofing, weak or missing encryption of sensitive data, sensitive data in clear text (to a Sidekiq job, say), vulnerable dependencies (it can look up advisories for the libraries in use), unchecked buffers in static languages, double free in C |

Each reviewer is given the spec, the plan, and the journal of decisions the implementing agents made (M2 of the memory decisions). The reviewers keep a journal of their own in `state.json` the same way, and so do luke and rey when they answer the review; `state.json` is committed with the plan, so the whole exchange is kept in git. Each ignores existing PR comments, including GitHub Copilot's, and reviews only the diff.

### R2. Every comment declares its verdict

The review opens with:

> Reviewed by <reviewer> using <model> by <provider> at <timestamp>.

for example "Reviewed by Hans Solo, reviewing agent, using Opus 5.5 by Anthropic at 2026/10/16 @ 12:34pm." Each comment starts with an emoji and its word, then the details, and a suggested change where one helps.

| Emoji | Word | Who | Means | Blocks |
| --- | --- | --- | --- | --- |
| ✅ | Great! | any | a particularly good solution, design or data structure; roughly the top 20% of the code, not every function | no |
| 🤔 | Hmmm... | any | worth thinking about: a question, a change to consider, a modest optimisation | no |
| ⛔️ | Must Fix | any | will break production: a fatal error such as an unchecked nil call, or a performance bug more than 10x off (O(n²) or worse where O(n log n) is possible on data that can be large). Fixed, or answered with why not | yes |
| 💣 | Security Flaw | vader only | an exploitable hole, including a dependency with a known, already-fixed vulnerability | yes |
| 🔓 | Security Concern | vader only | not exploitable now, but could become a vulnerability if misread later; rare | no |

These are PR comments, not GitHub reviews: the same account opens and reviews the PR.

## Labels

### R3. The verdict labels replace M3's

Two lifecycle labels stay, one is renamed:

| Label | Colour | Given when |
| --- | --- | --- |
| `ready-for-review` | `c2e0c6` | luke and rey are done, and the PR waits for a free review slot |
| `review-in-progress` | `FFBE20` | the reviewers have started; replaces `ready-for-review` |
| `ready-to-merge` | `5319e7` | chewie-verifier (M1) verified the PR and its E2E tests pass. Renamed from `ok-to-merge` |

`ready-to-merge` no longer means "passed with nothing open"; that verdict is now `review-approved`. The verdicts become:

| Label | Colour | Replaces | Given when |
| --- | --- | --- | --- |
| `review-rejected` | `F90000` | `review-rejected` (`b60205`) | at least one ⛔️ or 💣 |
| `review-vulnerability` | `FF0050` | new | at least one 💣; beside `review-rejected` |
| `review-ok-not-perfect` | `E8E890` | `review-passed` | no ⛔️ or 💣, more than five 🤔 |
| `review-approved` | `109a10` | `ready-to-merge` | anything else |

- The dispatcher makes sure every label exists on the repo, with these colours, when it starts on a project, and creates or updates any that do not match.
- `review-vulnerability` is the one exception to one label at a time: it sits beside `review-rejected`.
- The threshold of five 🤔 is a setting, overridable by an environment variable.
- The label is decided once all three reviewers have finished, from their comments counted together, in order: any ⛔️ or 💣 rejects; otherwise more than five 🤔 in total is `review-ok-not-perfect`; otherwise `review-approved`. A clean small PR is approved even if it earned no ✅.

## Quality

### R4. `desired_codebase_quality: high | mvp` replaces `build_quality`

- One key in `.openlanes.yml`. It replaces M5's `build_quality`, which was never stored: `high` takes M5's `high` column (models, depth, `max_rejections`), `mvp` its `mvp` column; `top_notch` and `medium` are dropped. hansolo stays on Opus at both levels (R1).
- `mvp` is not bad code; it goes through fewer hoops.
- What it decides at review:
  - `review-rejected` always goes back to luke and rey, at either level.
  - `review-approved` never goes back.
  - `review-ok-not-perfect`: under `mvp` the PR counts as done and goes on toward merging; under `high` it goes back to luke and rey.
- Sent back, for any reason, luke and rey answer every comment that is not ✅. A rebuttal (why the comment is misguided, wrong or does not apply) is an answer, and needs no code change, as long as the agent backs it up.
- Asked by `openlanes init`, or, when the key is missing, once per project, in the drawer, on the first PR labelled `review-ok-not-perfect`:

  > Please indicate the desired quality of the codebase (this affects the severity of items found during review that will require rework):
  >
  > 1. High quality, but slower and more expensive. A PR review labelled "review-ok-not-perfect" returns to developers for fixes.
  > 2. Good enough, but faster and cheaper, think MVP ("review-ok-not-perfect" is accepted, as it contains no blocking issues).
  >
  > NOTE: critical blocking issues or security issues identified during review will be addressed regardless.

## Merging

### R5. The engine auto-merges a passing PR that merges clean

- With `merge.by: agent`, the engine merges a PR once its verdict passes (`review-approved`, or `review-ok-not-perfect` under `mvp`), chewie-verifier has labelled it `ready-to-merge`, CI is green on the PR and on `main`, and it merges onto `main` without conflicts.
- Auto-merge only exists once chewie-verifier (plan 014) is built; until then nothing auto-merges. chewie is therefore built with very high priority.
- With `merge.by: human` nothing changes: the person merges (M4).
- The engine merges, never an agent (M2 stands).
- The only conflict check is that this PR merges clean. Changes big enough to collide with everything run alone (R6). After each merge the engine rebases the other open plan branches onto `main`, and conflicts left over are fixed in their next round.

### R6. A sweeping refactor runs alone

- A spec may say `implementation_requirement: refactor` in its front-matter. A refactor can move and rename classes and leave every other branch with conflicts nobody can resolve.
- palpatine-planner recognises a refactor, from that key or from what the spec asks for, and estimates the share of the codebase it touches, by files and by lines. Over 50% by either measure, it writes `execution: global-lock-required` into the plan's front-matter; otherwise `execution: concurrent`, the default. The 50% is a setting.
- A `global-lock-required` plan is built, reviewed and merged alone:
  - Once it is ready for luke, the dispatcher starts no new plan, and waits to hand it over until no other plan has an open branch or PR: each is merged or closed.
  - Plans that never started (no branch yet) do not count; they stay queued behind it.
  - A blocked plan that holds a branch holds the refactor up too, and the board says so, e.g. "refactor 031 waits on 018 ⭕".
  - Nothing else starts until the refactor is merged.
