# Decisions on merge modes, verification and project setup

Settled 2026-10-13 in a grilling session. Not built yet. Plans 005 and 007–016 implement it; their specs point here.

> [!IMPORTANT]
> **M3's labels are superseded by R3** (plan 030, `lib/openlanes/plans/review_label.rb`). Read every label name below with R3's meaning, not M3's:
>
> - `ready-to-merge` changed meaning. Under M3 it meant "review passed with nothing open". Under R3 it means "chewie-verifier verified it and its E2E tests pass", the role M3 gave `ok-to-merge`. Where M1, M2 and M5 say `ok-to-merge`, R3 says `ready-to-merge`; where they say `ready-to-merge`, R3 says `review-approved`.
> - `review-passed` is replaced by `review-ok-not-perfect`.
> - `review-passed` and `ok-to-merge` are retired (`ReviewLabel::RETIRED`): nothing sets them, and the next verdict on a pull request that still carries one takes it off. Label sync never deletes them from the repository.
> - Migrating a repository: relabel every pull request that carries M3's `ready-to-merge` as `review-approved` *before* any automatic merge reads R3's `ready-to-merge`, or a pull request that only passed review reads as verified.

Supersedes, in `decisions-on-web-ui-and-review-labels.md`:

- **L1:** the six labels are replaced by M3's six. `approved-despite-ci` is dropped, so there is no longer any way to approve over red CI.
- **L4:** reduced to its first half: no passing verdict over red CI. A rejection is still allowed.
- **W25:** only the default depth changes: it now comes from `build_quality` (M5). W25's mapping (Fast → `low`, Medium → `high`, Deep → `xhigh`) stands.

## Merging

### M1. A verifier agent drives the app before anything merges

- New agent `chewie-verifier`. It checks out a PR that review has passed, starts the app (M12), follows the PR's `## How to test` step by step, through a headless browser for web apps or a shell otherwise, and compares what it sees with what the steps promise.
- Pass: it applies `ok-to-merge`.
- Fail: it applies `review-rejected` and comments with what failed and a screenshot (M14). The plan goes to 🔴, and luke and rey get the comment.
- If the app does not start, that is a failure: "the app does not start", with the last 20 lines of its log.

### M2. The engine merges, never an agent

- In agent mode the engine merges a PR in code when it has `ok-to-merge`, its CI is green, `main`'s CI is green, and the merge is clean.
- `gh pr merge` stays in `UNGRANTABLE`. No agent can merge.

### M3. Six labels, one at a time per PR (superseded by R3)

| Label | Colour | Meaning |
| --- | --- | --- |
| `ready-for-review` | `c2e0c6` | PR open, review not started |
| `review-in-progress` | `fff3b0` light yellow | hansolo is reviewing |
| `review-passed` | `1d76db` blue | passed with non-critical findings still open |
| `ready-to-merge` | `2ea043` bright green | passed with nothing open |
| `review-rejected` | `b60205` deep red | changes needed |
| `ok-to-merge` | `1a7f37` | chewie verified it |

- Missing labels are created on first use. A new label replaces the previous one.
- No passing verdict (`review-passed`, `ready-to-merge`, `ok-to-merge`) is given while CI is red; `review-rejected` is.
- Labels are set through `openlanes review`, never raw `gh pr edit` (L3 stands).

### M4. Human mode is identical except for the merge

- `init` asks "Who merges PRs? A human, or an agent?" and stores `merge.by` in `.openlanes.yml`.
- Both modes run the same pipeline: review, the arbitrator, verification, labels and screenshots. In human mode the engine never merges; the human does.
- In human mode the engine polls every PR it opened, every 15 seconds, until the PR is merged or closed:
  - `review-rejected` with comments: the plan goes to 🔴, and luke and rey get the comments;
  - merged: ✅;
  - closed unmerged: ❌.
- While a PR waits on the human, Needs you shows "waiting on you: PR #N".

### M5. `build_quality` trades quality for speed

`init` asks for it and stores it in `.openlanes.yml`. A plan inherits it; the idea dialog's toolbar can change one plan, which writes that plan's `depth` and models into its spec.

| | `top_notch` | `high` | `medium` | `mvp` |
| --- | --- | --- | --- | --- |
| Verdicts that go on to verification (M1) | `ready-to-merge` only | `ready-to-merge` only | also `review-passed`, after the arbitrator's check (M9) | also `review-passed`, after the arbitrator's check |
| Default depth | deep | medium | medium | fast |
| luke, rey | Opus | Opus | Sonnet | Sonnet |
| hansolo | Opus, max effort | Opus | Sonnet | Sonnet |
| leah (research) | on | on | opt-in | off |
| `max_rejections` | 3 | 2 | 2 | 1 |
| Coverage minimum | 95% | 95% | 95% | 95% |

- Where only `ready-to-merge` goes on to verification, a `review-passed` PR goes back to luke and rey. Every merge still needs `ok-to-merge` (M2).
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
- **too harsh:** every open issue is cosmetic, so those findings are struck and it becomes `ready-to-merge`;
- **too lenient:** at least one open issue is critical, so it becomes `review-rejected` with that finding marked critical, and it counts toward the cap.

At `top_notch` and `high` the check is skipped, because a `review-passed` PR goes back for fixes anyway.

## What to test

### M10. Every spec says how to tell it works

- `spec.md` gains a `## How to tell it's working?` section. It becomes `## How to test` in `plan.md` and in the PR body.
- It replaces the `how-to-verify:` frontmatter key. Plan 007's `resync dirs` migrates old specs.
- The idea dialog has a "How will you tell it's working?" box. In the full lane it is optional: if it is left empty, yoda fills the section in. The `plan` and `quick` lanes skip yoda, so there the box is required, and the lane move (`Lifecycle::Lanes`) leaves a spec without the section at ⚪️.
- A plan cannot reach 📋 Ready for Planning without the section (status invariant).
- The publisher refuses to open a PR without `## How to test`, and hansolo rejects steps too vague to follow.

### M11. Verification depends on the kind of app

- Desktop: start the binary and check what it does.
- Data import: check the data is absent before and present after.
- Web: run a development preview and drive it (M13).

## Running the app

### M12. luke writes how to run the app

- The stack questionnaire (M16) records decisions, not commands, in `docs/decisions/stack.md` and as a `stack:` summary in `.openlanes.yml`.
- On the first build its builder (luke, or r2d2 in the `quick` lane) writes `app:` into `.openlanes.yml`: `kind`, and a list of `processes`, each with `name`, `start`, `ready`, `restart_on`, and `preview: true` on the one to show. hansolo rejects a first build without it.
- The engine starts the processes in order and waits for each to be ready. Each gets a free port from 11100 upward (`$PORT_<NAME>`). A process is restarted when its `restart_on` files change. Works with any stack: a TypeScript app, Astro, React with a Rust API, FastAPI, Go.

### M13. The Preview tab

- One tab per running app, next to Board and Logs, labelled with the plan, branch and port (`▶ 000 · kig/000.00-minesweeper`).
- A toolbar shows status (● running or restarting) and has Restart backend, Open in new window and Stop.
- An app that refuses to be framed opens in a separate browser window instead.
- While chewie drives its headless browser, the tab mirrors it with a screenshot about every 2 seconds.

### M14. Screenshots are PNG, committed with the plan

- `.plans/<plan>/verification/<round>/step-NN.png`, optimised with `vips` or `magick`, committed to the PR branch and linked from the comment by commit SHA, so they render in private repos too.
- Only the failing step and the final state are kept.
- PNG, not AVIF: GitHub does not render AVIF inline in Markdown or PR comments.

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

**Amended 2026-10-17, by the owner.** There is no `.openlanes.coverage.yml` any more, and no fallback to it. Coverage is the `coverage:` section of the project's `.openlanes.yml`, which holds one top-level key per config section. luke still writes it, and the gate reads it from the PR's checkout. `command` and `minimum` are required, plus exactly one of two shapes:

```yaml
coverage:                    # a command prints the line percentage
  command: bundle exec rspec
  report_command: cat coverage/coverage.json | jq '.total.lines.percent'
  minimum: 95
```

```yaml
coverage:                    # a report file, read by one of the parsers
  command: npm test -- --coverage
  report: coverage/coverage-summary.json
  format: istanbul           # lcov | cobertura | istanbul | simplecov
  minimum: 95
```

- `report_command` runs in the checkout after `command` succeeds. Its STDOUT must be one number from 0 to 100. Anything else (text, nothing, several numbers, a non-zero exit) counts as an unreadable report, and so as 0%, which is how a report a parser cannot read is handled too. A missing report still counts as 0%.
- `format` beside `report_command`, `report` beside `report_command`, `report` without `format` (or the reverse), neither shape, and any unknown key are each an error naming `.openlanes.yml` and the `coverage` section.
- No `coverage:` section is not a plain rejection. chewie sends the PR back to luke with one note: add a `coverage:` section to `.openlanes.yml` for this stack, with both shapes shown. The PR is still labelled `review-rejected` and the plan goes to 🔴, but this send-back does not count against `merge.max_rejections`. It is a setup gap, not a defect in the code, and counting it would bring a plan nearer the arbitrator (M6) for something the build never got wrong. Once luke writes the section, the gate works as above.

## Project setup

### M16. `lanes init` interviews in the terminal through inquirex-tty

- Questions, in order: who merges (M4), build quality (M5), then the stack.
- The stack: detect what the folder already holds, then ask whether the user is set on it or open to alternatives. If they are open, or the folder is empty, a questionnaire covers language, frameworks, layers, persistence, caching, front end, logins, deployment and domain.
- It opens with a free-text "Describe the app you want to build". inquirex-llm turns that into answers to later questions, which are then skipped.
- Extraction needs `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`. With neither, `init` says so once and asks every question. openlanes picks the adapter itself, so inquirex's `NullAdapter` never fills in placeholder answers.
- inquirex-tty offers dropdowns, single and multiple selects. Between questions it prints a green tip: "Press Cmd-Backspace to go backwards and change your answers". Before relying on that key, check that iTerm and Terminal.app deliver Cmd-Backspace to the program; if they don't, pick a key that arrives. The web widget already has a back button.
- `lanes init --reconfigure` re-runs the interview with the current answers as defaults and shows what changed. `.openlanes.yml` is re-read every round, so a hand edit takes effect without a restart.
- v2.0: the same questionnaire in the web copilot, using a flow built in qualified.at with its JS loaded locally, with extraction done by the openlanes server behind a narrow localhost endpoint. The API key never reaches the browser, where any script or extension could read it.

### M17. The inquirex gems are fixed upstream

They are local in `/Users/kig/github/inquirex`; the Ruby gems are versioned together where practical, separately from npm.

1. `inquirex-tty` 0.10.0 requires `inquirex ~> 0.9.5`, so it cannot be installed with `inquirex` 0.10.0.
2. inquirex-llm's default model ids are outdated (`claude-sonnet-4-20250514`).
3. `inquirex-tty` has no non-interactive mode (preset answers, `--yes`), and writes results to stderr.
4. `inquirex-tty`'s README sample output uses a real name and email.
5. Going back: the Ruby engine keeps a history but has no `back`.

### M18. Porting a project to another stack

- When an existing stack is detected and the user is open to alternatives, `init` asks whether to port the code or start fresh beside it.
- A port records `from` and `to` in `docs/decisions/stack.md` and opens with a generated "Port from X to Y" plan: leah inventories the old code, luthen-rael splits it into units.
- Both apps run side by side. chewie checks parity: each unit's test steps run against both, and their outputs must match.
- Coverage counts the new stack only. Retiring the old app is the last plan, and it always goes to the human before merging.

### M19. Later

- An `openlanes gc` command became plan aging and archiving (plans 007–009).
- A Settings dialog in the control room comes with v2.0.

### M20. Prose under "How to tell it's working?" is a check

Decided by the owner, 2026-10-14: "The more specific and technical how to test is, the better. Prose can be pretty specific."

- Every list item under `## How to tell it's working?` is one check, with its continuation lines and any fenced block under it.
- Every prose paragraph is one check too, kept verbatim. Prose is no longer discarded as commentary.
- A fenced block not under a list item belongs to the paragraph before it, or stands as its own check.
- Built in plan 007 (`Spec.section_items`); supersedes plan 005's rule that read bullets only, falling back to plain lines when there were none.

### M21. `init` settles CI first

Decided by the owner, 2026-10-14. Many projects have no CI, and without it a pull request has no checks for the review gate to read.

- `init` first detects an existing CI setup (GitHub Actions, CircleCI, Jenkins, GitLab CI, Buildkite) and, when it finds one, asks nothing about CI.
- Otherwise it is one of the first questions: "Do you have a CI setup, or would you like some help with that?" Choosing help asks which CI: GitHub Actions, CircleCI, or a third option (proposed: Jenkins, to confirm). openlanes then writes that provider's config, running the project's own lint and test commands.
- The answer is recorded in `.openlanes.yml` as `ci.provider` (and `ci.config` when a file was written).
- Proposed, to confirm: when a project has no CI, a passing review label requires local verification (plan 014) instead of being treated as green.
- Built in plan 011.
