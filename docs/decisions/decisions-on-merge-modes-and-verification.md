# Decisions on merge modes, verification and project setup

Settled 2026-10-13 in a grilling session. Not built yet. Plans 005 and 010–016 implement it; their specs point here.

Supersedes, in `decisions-on-web-ui-and-review-labels.md`:

- **L1:** the six labels are replaced by M3's six. `approved-despite-ci` is dropped, so there is no longer any way to approve over red CI.
- **L4:** reduced to its first half: no verdict over red CI.
- **W25:** depth still maps to effort, but a plan's default depth now comes from `build_quality` (M5).

## Merging

### M1. A verifier agent drives the app before anything merges

- New agent `chewie-verifier`. It checks out a PR that review has passed, starts the app (M12), follows the PR's `## How to test` step by step, through a headless browser for web apps or a shell otherwise, and compares what it sees with what the steps promise.
- Pass: it applies `ok-to-merge`.
- Fail: it applies `review-rejected` and comments with what failed and a screenshot (M14). The plan goes to 🔴, and luke and rey get the comment.
- If the app does not start, that is a failure: "the app does not start", with the last 20 lines of its log.

### M2. The engine merges, never an agent

- In agent mode the engine merges a PR in code when it has `ok-to-merge`, its CI is green, `main`'s CI is green, and the merge is clean.
- `gh pr merge` stays in `UNGRANTABLE`. No agent can merge.

### M3. Six labels, one at a time per PR

| Label | Colour | Meaning |
| --- | --- | --- |
| `ready-for-review` | `c2e0c6` | PR open, review not started |
| `review-in-progress` | `fff3b0` light yellow | hansolo is reviewing |
| `review-passed` | `0b6e2e` deep green | passed with non-critical findings still open |
| `ready-to-merge` | `2ea043` bright green | passed with nothing open |
| `review-rejected` | `b60205` deep red | changes needed |
| `ok-to-merge` | `1a7f37` | chewie verified it |

- Missing labels are created on first use. A new label replaces the previous one.
- No verdict is given while CI is red.
- Labels are set through `openlanes review`, never raw `gh pr edit` (L3 stands).

### M4. Human mode is identical except for the merge

- `init` asks "Who merges PRs? A human, or an agent?" and stores `merge.by` in `.openlanes.yml`.
- Both modes run the same pipeline: review, the arbitrator, verification, labels and screenshots. In human mode the engine never merges; the human does.
- In human mode the engine polls open PRs every 15 seconds:
  - `review-rejected` with comments: the plan goes to 🔴, and luke and rey get the comments;
  - merged: ✅;
  - closed unmerged: ❌.
- While a PR waits on the human, Needs you shows "waiting on you: PR #N".

### M5. `build_quality` trades quality for speed

`init` asks for it and stores it in `.openlanes.yml`. A plan inherits it; the idea dialog's toolbar can change one plan, which writes that plan's `depth` and models into its spec.

| | `top_notch` | `high` | `medium` | `mvp` |
| --- | --- | --- | --- | --- |
| PRs that reach merge | `ready-to-merge` only | `ready-to-merge` only | also `review-passed`, after the arbitrator's check (M9) | also `review-passed`, after the arbitrator's check |
| Default depth | deep | medium | medium | fast |
| luke, rey | Opus | Opus | Sonnet | Sonnet |
| hansolo | Opus, max effort | Opus | Sonnet | Sonnet |
| leah (research) | on | on | opt-in | off |
| `max_rejections` | 3 | 2 | 2 | 1 |
| Coverage minimum | 95% | 95% | 95% | 95% |

- Where only `ready-to-merge` reaches merge, a `review-passed` PR goes back to luke and rey.
- The coverage minimum is the same at every level. MVP speed comes from cheaper models and fewer rounds, not fewer tests.

### M6. Rejections are capped

- `merge.max_rejections` in `.openlanes.yml`, defaulting from M5's table and not asked at `init`. It counts rejections from hansolo and chewie together.
- The control room shows "rejected 2 of 2" on the plan.
- When the cap is reached, the arbitrator rules (M8).

## Arbitration

### M7. `obi-wan-kenobi-arbitrator`

A read-only agent on Opus that settles disputes. Each ruling is a dated entry in the plan's `state.json` and a PR comment. It has no write tools; the engine applies whatever label follows from a ruling.

### M8. What it settles in v1

1. **The rejection cap.** It reads the spec, the PR, both reviewers' comments and the screenshots, then rules:
   - go: `ready-to-merge`, one last verification, and if that fails the plan goes to the human;
   - no-go: the PR stays `review-rejected`, and the plan goes under Needs you with the ruling.
2. **A builder's appeal.** luke or rey writes `appeal: <finding> because <reason>` in the ledger. The finding is upheld or struck.
3. **luke versus rey** on the API between them.

Spec drift is left to plan aging (`decisions-on-plan-folder-naming.md`, N8). Blocked product questions stay with the human.

### M9. A `review-passed` verdict is checked before anything acts on it

At `medium` and `mvp` the arbitrator reads hansolo's open findings on every `review-passed` PR and rules:

- **fair:** the label stands;
- **too harsh:** every open issue is cosmetic, so it becomes `ready-to-merge`;
- **too lenient:** at least one open issue is critical, so it becomes `review-rejected` with that finding marked critical, and it counts toward the cap.

At `top_notch` and `high` the check is skipped, because a `review-passed` PR goes back for fixes anyway.

## What to test

### M10. Every spec says how to tell it works

- `spec.md` gains a `## How to tell it's working?` section. It becomes `## How to test` in `plan.md` and in the PR body.
- It replaces the `how-to-verify:` frontmatter key. Plan 007's `resync dirs` migrates old specs.
- The idea dialog has an optional "How will you tell it's working?" box. If it is left empty, yoda fills the section in.
- A plan cannot reach 📋 Ready for Planning without the section (status invariant).
- The publisher refuses to open a PR without `## How to test`, and hansolo rejects steps too vague to follow.

### M11. Verification depends on the kind of app

- Desktop: start the binary and check what it does.
- Data import: check the data is absent before and present after.
- Web: run a development preview and drive it (M13).

## Running the app

### M12. luke writes how to run the app

- The stack questionnaire (M16) records decisions, not commands, in `docs/decisions/stack.md` and as a `stack:` summary in `.openlanes.yml`.
- On the first build luke writes `app:` into `.openlanes.yml`: `kind`, and a list of `processes`, each with `name`, `start`, `ready`, `restart_on`, and `preview: true` on the one to show. hansolo rejects a first build without it.
- The engine starts the processes in order and waits for each to be ready. Each gets a free port from 11100 upward (`$PORT_<NAME>`). A process is restarted when its `restart_on` files change. Works with any stack: a TypeScript app, Astro, React with a Rust API, FastAPI, Go.

### M13. The Preview tab

- One tab per running app, next to Board and Logs, labelled with the plan, branch and port (`▶ 000 · kig/000.00-minesweeper`).
- A toolbar shows status (● running or restarting) and has Restart backend, Open in new window and Stop.
- An app that refuses to be framed opens in a separate browser window instead.
- While chewie drives its headless browser, the tab mirrors it with a screenshot about every 2 seconds.

### M14. Screenshots are AVIF, committed with the plan

- `.plans/<plan>/verification/<round>/step-NN.avif`, converted with `vips` or `magick`, committed to the PR branch and linked from the comment by commit SHA, so they render in private repos too.
- Only the failing step and the final state are kept.

### M15. Coverage is read from a declared report

`.openlanes.coverage.yml`, written by luke:

```yaml
command: npm test -- --coverage
report:  coverage/coverage-summary.json
format:  istanbul        # lcov | cobertura | istanbul | simplecov
minimum: 95
```

- The engine runs `command` in a clean checkout of the PR and reads `report`. A missing report counts as 0%.
- Below `minimum` there is no `ok-to-merge`. hansolo rejects any change that lowers `minimum`.

## Project setup

### M16. `lanes init` interviews in the terminal through inquirex-tty

- Questions, in order: who merges (M4), build quality (M5), then the stack.
- The stack: detect what the folder already holds, then ask whether the user is set on it or open to alternatives. If they are open, or the folder is empty, a questionnaire covers language, frameworks, layers, persistence, caching, front end, logins, deployment and domain.
- It opens with a free-text "Describe the app you want to build". inquirex-llm turns that into answers to later questions, which are then skipped.
- Extraction needs `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`. With neither, `init` says so once and asks every question. openlanes picks the adapter itself, so inquirex's `NullAdapter` never fills in placeholder answers.
- inquirex-tty offers dropdowns, single and multiple selects. Between questions it prints a green tip: "Press Cmd-Backspace to go backwards and change your answers". Before relying on that key, check that iTerm and Terminal.app deliver Cmd-Backspace to the program; if they don't, pick a key that arrives. The web widget already has a back button.
- `lanes init --reconfigure` re-runs the interview with the current answers as defaults and shows what changed. `.openlanes.yml` is re-read every round, so a hand edit takes effect without a restart.
- v2.0: the same questionnaire in the web copilot, using a flow built in qualified.at with its JS loaded locally, with extraction in the browser. That is acceptable only while the page is served on localhost, because the API key reaches the browser.

### M17. The inquirex gems are fixed upstream

They are local in `/Users/kig/github/inquirex`; the Ruby gems are versioned together where practical, separately from npm.

1. `inquirex-tty` 0.10.0 requires `inquirex ~> 0.9.5`, so it cannot be installed with `inquirex` 0.10.0.
2. inquirex-llm's default model ids are outdated (`claude-sonnet-4-20250514`).
3. `inquirex-tty` has no non-interactive mode (preset answers, `--yes`), and writes results to stderr.
4. `inquirex-tty`'s README sample output uses a real name and email.
5. Going back: the Ruby engine keeps a history but has no `back`.

### M18. Porting a project to another stack

- When an existing stack is detected and the user is open to alternatives, `init` asks whether to port the code or start fresh beside it.
- A port records `from` and `to` in `docs/decisions/stack.md` and opens with a generated "Port from X to Y" plan: leah inventories the old code, palpatine splits it into units.
- Both apps run side by side. chewie checks parity: each unit's test steps run against both, and their outputs must match.
- Coverage counts the new stack only. Retiring the old app is the last plan, and it always goes to the human before merging.

### M19. Later

- An `openlanes gc` command became plan aging and archiving (plans 007–009).
- A Settings dialog in the control room comes with v2.0.
