## How every reviewer works

Up to three reviewers read this pull request at once, each from its own angle and perhaps on a different coding agent: `staff-reviewer` (correctness, readability, runtime failures, performance), `security-reviewer` (vulnerabilities) and `design-reviewer` (code organisation and systems design). Review from yours alone; the others cover theirs.

- Review the diff (`gh pr diff <n>`), not the codebase. Code the diff does not touch is out of scope unless the diff breaks it.
- Ignore the comments already on the pull request, from people or other reviewers: judge the code, not the conversation.
- Never run `openlanes review` or `gh pr edit`. You report a verdict; the engine labels the pull request once every reviewer has reported, from all the verdicts together, so no two reviewers race each other's labels.

### Your comment

Leave one PR comment (`gh pr comment <n>`), never a GitHub review: the same account opened the pull request. It opens with:

> Reviewed by <your name> using <model> by <provider> at <YYYY/MM/DD @ h:mmam>.

The model and its provider are the ones you run on, named under `## Rejection cap` in your invocation. Then one entry per point, each opening with its emoji and word, then the details, and a suggested change where one helps:

| Emoji | Word             | Means                                                                                                                                                                          | Blocks |
| :---- | :--------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----- |
| ✅     | Great!           | a particularly good solution, design or data structure; roughly the top 20% of the code, not every function                                                                    | no     |
| 🤔    | Hmmm...          | worth thinking about: a question, a change to consider, a modest optimisation                                                                                                  | no     |
| ⛔️    | Must Fix         | will break production: a fatal error such as an unchecked nil call, or a performance bug more than 10x off (O(n²) or worse where O(n log n) is possible on data that can be large) | yes    |
| 💣    | Security Flaw    | `security-reviewer` only: an exploitable hole, including a dependency with a known, already-fixed vulnerability                                                                 | yes    |
| 🔓    | Security Concern | `security-reviewer` only: not exploitable now, but could become a vulnerability if misread later; rare                                                                         | no     |

### Your findings

Write your findings in `pull-requests.md` under `## Findings: <your name>`, a section of your own, so reviewers working in one checkout never write over each other. Every ⛔️ and 💣 is a `critical` finding; a 🤔 worth tracking is a `minor` one.

Each finding opens with its own heading, `### F<n> [critical|minor] <file>:<line>`, numbered from your first id (in your own instructions above), then says what is wrong and gives a failing scenario: input, expected, actual. A finding without a scenario is an opinion; drop it. An untagged finding is read as critical. Never raise again a finding your invocation lists as struck by the arbitrator; it names each by the review round that raised it and its heading, so match on what the finding says, not on its id. If you find nothing after trying, write "no findings" under your section.

### Verdict

Count the earlier review rounds that rejected this PR: the `rejected` notes in `openlanes state show --plan NNN` (under `signatures`), counting notes signed together by several reviewers as one round, plus any `(rejected` notes in `pull-requests.md` from before signatures moved there. Then pick one:

| Condition                                                | Do                                                     | Sign                                  |
| :------------------------------------------------------- | :----------------------------------------------------- | :------------------------------------ |
| a critical finding, K earlier rejected rounds            | the comment above, listing each finding                | `Completed, round R (rejected K+1/M)` |
| only minor findings, or none, and nothing to admire      | the comment above                                      | `Completed, round R (passed)`         |
| no findings, and the code is a pleasure to read          | the comment above, ending "👍🏼 to deploy"               | `Completed, round R (great)`          |
| code missing, not working, untested, or off-spec         | write `rewrite.md` saying why, then the comment above  | `Completed, round R (slop)`           |

R is this review's round and M is `merge.max_rejections`, given under `## Rejection cap` in your invocation: with M 2, the first rejection signs `(rejected 1/2)` and the second `(rejected 2/2)`. A plan at the cap goes to the arbitrator, not back to you, so keep reviewing on findings alone.

If `pull-requests.md` lists several PRs, judge each, and sign the worst verdict any of them earned.

The engine adds your verdict to the other reviewers': any `rejected` or `slop` labels the pull request `review-rejected`; otherwise it is `review-approved` when most of you said `great`, and `review-passed` when not. A passing label is refused while CI is red, and the plan goes back to its builders.

### Done when

- [ ] Every check in your own instructions ran, and every finding has a failing scenario.
- [ ] Your comment is on the pull request, opening with the "Reviewed by" line.
- [ ] You signed `Completed` with exactly one of the four notes above as `--note`. The harness reads the word in the note.

### Next

| Verdict             | Folder becomes | Who runs next                                                                                 |
| :------------------ | :------------- | :-------------------------------------------------------------------------------------------- |
| `rejected`          | 🔴 Rejected    | `backend-coder` and `frontend-coder` fix every reviewer's findings, then you all review again |
| `great` or `passed` | 🧪 Verifying   | `verifier` runs the app through How to test; nobody merges before it passes. No agent merges. |
| `slop`              | 🚫             | a human reads `rewrite.md` and decides. No agent handles 🚫.                                  |

Until the last reviewer reports, the folder stays at 👀 whatever you signed.
