---
depends_on: ["005.00", "012.00", "013.00"]
---

# Chewie Verifier

## What we are trying to achieve

`chewie-verifier` checks out a PR that passed review, starts the app, follows `## How to test`, and labels it `ready-to-merge` or rejects it with a PNG screenshot. In agent mode the engine then merges; rejections are capped.

## Why it matters

A review reads the diff, but nobody runs the app before it merges.

## What already exists

- Decisions M1, M2, M4, M6, M11 and M14 in `docs/decisions/decisions-on-merge-modes-and-verification.md`.
- `lib/openlanes/execution/executor.rb`: `UNGRANTABLE` keeps `gh pr merge` away from agents.

## What research needs to settle

- Browser automation for the agent (Cypress, Playwright, or Chrome DevTools).
- Converting screenshots to PNG, and committing them through the publisher.
- The engine's merge checks, and the 15-second PR poll in human mode.

## How to tell it's working?

- A fixture project with a two-process web app (012's `spec/fixtures/apps/` servers) and a PR whose `## How to test` steps pass: after hansolo signs `approved`, the folder moves 👀 → 🧪, the app starts, chewie signs `Completed (verified)`, the engine pushes one commit adding `verification/1/final.png`, and once the fake `gh` reports CI green the PR carries exactly one review label, `ready-to-merge`.
- Same fixture with `merge.by: auto`: the fake `gh` records exactly one `gh pr merge` call, issued by the engine process, after the PR's checks and the status of `main`'s HEAD both read green and `mergeStateStatus` is `CLEAN`; the folder ends at ✅. With `merge.by: human` the fake `gh` records no merge call and the board shows "waiting on you: PR #N".
- `main` red, or the PR not `CLEAN`: no merge call; the plan stays 🧪 and the board says which check holds it.
- A PR whose steps fail: the PR gets `review-rejected` and one comment naming the failing step and linking `verification/1/step-NN.png` by commit SHA; the PNG is in the PR branch; the folder moves to 🔴 and the comment is mailed to luke and rey.
- An `app:` whose process never becomes ready: the same rejection, with "the app does not start" and the last 20 lines of that process's output in the comment.
- With `merge.max_rejections: 2`, the second rejection (hansolo's and chewie's counted together) does not send the plan back to luke and rey; the board shows "rejected 2 of 2" and the plan waits under Needs you for the arbitrator.
- `bundle exec rspec` and `just lint` stay green; `bin/coverage-changed` passes on the changed `lib/` files.

## Framings considered

1. **A folder state.** A new 🧪 Verifying state between 👀 and ✅, handled by `chewie-verifier`. The engine moves the folder there on hansolo's approved verdict, and from there to 🔴 on a rejection or ✅ on a merge.
1. **A label phase inside 👀.** No new state: chewie also handles `in_review`, and the PR's labels say whose turn it is.

**Chosen: 1.** The engine routes work by state (`handles:` through the registry into `Dispatcher#start`), so two agents handling 👀 would need a second router keyed by labels. A state also puts "verifying" on the board and on Linear without new code paths. The cost is the fixed "When adding a state" checklist in `CLAUDE.md`, which this plan follows.

## Goal

A PR that passed review is run before it merges. The engine starts the plan's app (plan 012), hands the running app and the PR's `## How to test` to a new `chewie-verifier` agent, and acts on its verdict. On a pass it commits the final screenshot, waits for CI, consults plan 013's coverage gate and applies `ready-to-merge`. On a fail it commits the failing step's PNG, comments with it, applies `review-rejected` and sends the plan to 🔴. In agent mode (`merge.by: auto`) the engine itself merges an `ready-to-merge` PR once its CI, `main`'s CI and the merge are all clean; in human mode it waits for the human. Rejections from hansolo and chewie are counted against `merge.max_rejections`. Today an approved plan stops at 👀, nothing runs the app, and nothing merges (research, "Where verification sits today").

## Non-Goals

- **No agent merges, pushes or commits.** `gh pr merge` and `git push` stay in `UNGRANTABLE` (`executor.rb:338`); chewie gets neither, nor `git commit`.
- **Not the arbitrator.** Ruling on the cap, appeals and `review-passed` checks is plan 015 (M7–M9). This plan stops at the cap and leaves a seam.
- **Not `build_quality`.** M5's table, and its per-level choice of which verdicts go on to verification, belong to the `init` work (plan 011, M16). Here only `review-approved` goes on to verification: M5's rule at `top_notch` and `high`, and the only passing label hansolo applies (005 `hansolo-reviewer.md:42-47`).
- **Not the app runner.** Starting, ports, readiness and restart are 012's `Apps::Supervisor`; this plan calls it.
- **Not the coverage gate.** Parsing reports is 013; this plan calls its gate before applying `ready-to-merge`.
- **No port parity checks (M18).** Running steps against two stacks is later work (plan 016).
- **No deploy.** ✅ → 😎 stays a human's.

## In scope

This plan covers items 1–7 and 11–14. It verifies through the shell when there is no browser. Items 8–10 (browser, mirroring) belong to 014.01, and items 15–18 (merge, rejection cap, control room) belong to 014.02. Those two plans can be built side by side once this one lands.

Decided 2026-10-15 by kig: split 014 into three plans as above, one pull request each, with the browser and the merge-and-cap work in their own plans.

Each item has its check. "Fake `gh`" is 005's `spec/support/fake_gh/gh`.

1. **State.** `STATUSES` gains `verifying` (🧪 Verifying, requires `spec.md plan.md pull-requests.md`, invariant `open_pull_request("Verifying")`). Events: `verify` (`in_review` → `verifying`); `request_changes` and `approve` also accept `from: verifying`. Check: `state_machine_spec` asserts the three edges and that `verifying` joins `in_review`'s `FAMILIES` group (`state_machine.rb:93-96`), so `resync dirs` never moves a folder out of it.
2. **Derived tables.** `verifying` placed in `linear/mapping.rb` `PLACEMENTS` (started, "In Review") and in the "Review" station (`live/stations.rb:40`). Check: `mapping_spec.rb:11-17` passes; `openlanes docs` and `openlanes states` regenerate with 🧪 and no hand edits.
3. **Hand-off.** On hansolo's `approved` verdict the dispatcher promotes 👀 → 🧪 instead of finishing the plan (`dispatcher.rb:1090-1093`), and hansolo's Next table says so. Check: dispatcher spec, approved verdict, folder renamed to 🧪 and `@finished_plans` does not include it.
4. **Agent definition.** `agents/chewie-verifier.md`: `handles: [verifying]`, `advances_to: approved`, `phase: verification`, `adapter: claude`, `allowed_tools` limited to Read, Grep, Glob, Bash, Write and the Chrome DevTools MCP tools; no `may:`; `writes: [verification/**]`. Its prompt: follow `## How to test` step by step, screenshot each step into `<plan folder>/verification/<round>/step-NN.png`, keep the failing step and `final.png`, write `verification/<round>/report.md`, sign `Completed (verified)` or `Completed (rejected)`. Check: `registry_spec` loads it; the prompt-content spec asserts both signature notes; an eval case under `evals/cases/chewie-verifier/` (required by `corpus_spec.rb:14`).
5. **Verdicts.** `verdict_of` recognises the verification phase: "verified" is a pass, "reject" a fail (`dispatcher.rb:1161-1178`). Check: dispatcher spec per note.
6. **App start.** Entering 🧪, the engine starts the app in the plan's checkout through `Apps.supervisor` (012 B4), and stops it when the agent finishes, whatever the outcome. Check: spec with the 012 fixture asserts the app is running during the agent call, and that afterwards no child is alive and no port is reserved.
7. **App fails to start.** `Supervisor::StartFailed` produces a rejection with "the app does not start", the reason, and the last 20 lines of the failing process's output, without calling the agent. Needs a `#log_tail(name, lines)` on the supervisor, which this plan adds if 012 has not. Check: never-listening fixture; comment body asserted.
8. **Per-agent MCP.** A new `mcp:` frontmatter key (registry) names servers; the claude adapter replaces the empty `--mcp-config` (`claude.rb:50-52`) with a config holding only those servers. Agents without `mcp:` get exactly today's argv. Check: adapter spec for both cases, argv identical when the key is absent.
9. **Browser.** For an `app:` with a `preview: true` process, the engine launches headless Chrome with a temporary profile and a remote-debugging port from 012's registry, and starts the MCP server with `--browserUrl` pointing at it. The prompt carries the preview URL and every `PORT_<NAME>`. Without a preview process the prompt says to verify through the shell (M11), and no browser starts. Check: spec on the built prompt and the MCP config for both cases.
10. **Mirroring (M13).** While the browser runs, the engine captures a CDP screenshot about every 2 s and publishes it as a new `app.frame` SSE event (`plan`, `png` as base64, `at`); the Preview tab shows the latest frame for that plan while chewie runs. Check: events spec for the cadence with an injected clock; a vitest in `web/src/preview/`.
11. **Screenshots.** The engine optimises every PNG under `verification/<round>/` with `vips` (falling back to `magick`, and skipping with a warning if neither exists), refuses non-PNG images there, and keeps only the failing `step-NN.png` and `final.png`. Check: spec with a fixture PNG asserts the file does not grow, and that an `.avif` is refused.
12. **Commit and push.** A publisher method commits the plan folder only (carried as today, `publisher.rb:141-171`), pushes, and returns the SHA. It refuses when the checkout has changes outside the plan folder (chewie must not edit code), and it is not a resubmit (`label_for_review` is not called). Check: publisher spec refusing a stray code edit, and a clean run returning the SHA.
13. **Rejection path.** After the push, a new `GitHub#comment` posts the failing step, what was expected and what was seen, and the PNG linked as `https://github.com/<repo>/blob/<sha>/<url-encoded path>?raw=true`; then `Vcs.review` applies `review-rejected`; the folder goes to 🔴 and the comment is mailed to luke and rey through `PrOutcomes`. Check: fake `gh` records the comment, then the label; folder at 🔴; mailbox entries for both.
14. **Pass path.** After the push the plan stays 🧪 until PR CI is green; then the 013 coverage gate runs; on a pass `Vcs.review` applies `ready-to-merge`, otherwise the PR is rejected with the gate's message. Check: fake `gh` going pending → green; gate stubbed to pass and to fail.
15. **Merge (agent mode).** A merge step, polled every 15 s like `PrWatch`, merges a 🧪 PR when it carries `ready-to-merge`, `CiGate` is green, `main`'s HEAD is green (a new `GitHub#commit_status`, reading statuses and check runs), and `mergeStateStatus` is `CLEAN`, through a new `GitHub#merge(number:, repo:)`. It then records "merged" and promotes to ✅. Check: one spec per failing condition, each with no merge call; a spec asserting `Executor::UNGRANTABLE` still includes `gh pr merge`.
16. **Human mode.** With `merge.by: human` the merge step never calls `GitHub#merge`; 005's `PrWatch` moves the plan to ✅ when the human merges, and the board shows "waiting on you: PR #N". Check: spec with fake `gh` flipping the PR to merged.
17. **Rejection cap.** `merge.max_rejections` is accepted under `merge:` (`config.rb:214-226`, 005), default 2. The count is derived from the ledger, never stored: hansolo's and chewie's `Completed` signatures with a rejected note on this plan. At the cap the plan is not sent back to the builders; it waits under Needs you, the board shows "rejected N of M", and an `Engine::Arbitration` seam (`call(plan:)`) is invoked, whose default only records the wait. Check: config spec for the key; dispatcher spec at counts 1 and 2.
18. **Control room.** The board snapshot carries `rejections: { count, max }` per plan; the plan card shows "rejected N of M", and 🧪 plans render in the Review station. Check: vitest on the card.

## Out of scope

- **The arbitrator's rulings (M7–M9).** Plan 015 replaces item 17's default seam.
- **`build_quality`, and `review-passed` going on to verification.** Needs M5's config (plan 011) and M9's check (plan 015).
- **`init` asking `merge.by`.** Plan 011; this plan reads the key 005 added.
- **CDP screencast (`Page.startScreencast`).** 012's research found its ack protocol unproven; the 2-second poll ships first.
- **Running chewie on codex or pi.** Only the claude adapter has an MCP switch (research); `adapter: claude` pins it.
- **Fixing the "no new remote ref" claim** in `executor.rb:16-20` and `CLAUDE.md`. A real contradiction (research), unrelated to verification; worth its own small PR.

## Back end / front end

| Item | Built by |
| :--- | :--- |
| 1, 2 State and derived tables | `luke-backend` |
| 3, 5 Hand-off and verdicts | `luke-backend` |
| 4 Agent definition and eval case | `luke-backend` |
| 6, 7 App start, log tail | `luke-backend` |
| 8, 9 MCP config, browser launch, prompt | `luke-backend` |
| 10 Mirroring | `luke-backend` captures and emits `app.frame`; `rey-frontend` shows it in the Preview tab |
| 11–14 Screenshots, commit, rejection and pass paths | `luke-backend` |
| 15, 16 Merge step, human mode | `luke-backend` |
| 17 Rejection cap | `luke-backend` |
| 18 Control room | `luke-backend` adds `rejections` to the snapshot; `rey-frontend` renders the card |

The pair fixes the `app.frame` payload and the `rejections` field before either builds against them.

## Open questions

Each has a recommendation, which the spec above assumes until the owner says otherwise. None is an owner decision yet.

1. **State or label phase** (leah 1). Recommended: a state, `verifying`, emoji 🧪, as chosen above. 🧪 is not in `STATUSES`, so `STATUS_BY_EMOJI` (`status.rb:338`) stays unambiguous.
2. **Who applies labels and comments** (leah 2). Recommended: the engine, from chewie's signed verdict and `report.md`. M1 says chewie applies them, but the SHA link (M14) and the CI wait after the screenshot push (research, contradictions 2 and 3) cannot happen inside the agent's run. Alternative: grant chewie `gh pr comment` and `openlanes review`, and drop the SHA links.
3. **The cap before plan 015** (leah 3). Recommended: stop at the cap, show "rejected N of M" under Needs you, call a no-op `Engine::Arbitration` seam that 015 fills. Alternative: hand the plan to the human with no seam.
4. **Default `max_rejections`** (leah 4). Recommended: 2, the value M5 gives `high` and `medium`. M5's table replaces it when `build_quality` lands.
5. **Merge method and branch** (leah 5). Recommended: `gh pr merge --merge`, matching this repository's merge commits; keep the branch. Alternative: `--squash`.
6. **No `app:` block** (leah 6). Recommended: chewie still runs and follows `## How to test` in the shell, as for a desktop or CLI app (M11); openlanes itself is a CLI gem with no `app:`. Alternative: reject, matching M12's rule that hansolo rejects a first build without `app:`.
7. **Merge conflict at merge time** (leah 7). Recommended: back to 🔴 with a "rebase on main" comment, not counted as a rejection. Alternative: Needs you.
8. **Installing `chrome-devtools-mcp`** (leah 8). Recommended: pinned at 0.19.0 (the version cached locally), installed by `bin/setup`, and started from that install, never `npx …@latest` during an agent run. Alternative: require the plugin on the machine.
9. **Chrome location.** Recommended: `/Applications/Google Chrome.app` on macOS, `google-chrome` on `PATH` elsewhere, overridable by `OPENLANES_CHROME`. No decision covers it.
10. **Mirroring frame size.** Recommended: downscale frames to 1024 px wide before base64, so a 2-second stream stays small on SSE. Not measured.
11. **Which `main` checks count.** Recommended: every status and check run on `main`'s HEAD, through `CiGate.verdict`'s rules, so "no checks" reads `:none` and passes with a warning, as 005 does for PRs.

### B1 (answered) — Where the suite gets run

The agent sandbox accepts every TCP connect to 127.0.0.1, so the socket-dependent specs (012's app runner, the app session, the verification integration spec) cannot prove a port is free. Options: a) a human runs `bundle exec rspec` and `bin/coverage-changed` in the worktree from a normal terminal; b) allow localhost in the agent sandbox; c) skip the socket examples when localhost answers.

### D1 (decision) — Where the suite gets run

Answered:

- 2026-10-20, 17:07 PDT
- By kig

Option a. A human runs `bundle exec rspec` and `bin/coverage-changed` in the worktree from a normal terminal. If both are green, luke re-runs and signs `Completed`. The agent sandbox does not run the socket-dependent specs, and no examples are skipped.

______________________________________________________________________

## Risks to planning or execution

- **Three unmerged dependencies.** 005 (PR #26) is open; 012 and 013 have plans but no code. Every interface named here (`Vcs.review`, `CiGate`, `PrWatch`, `PrOutcomes`, `Apps.supervisor`, the coverage gate) may move before it lands. The planner should start with items that touch none of them (1–5, 8) and pin the rest to the merged names.
- **CI churn from the screenshot commit.** Every verification push starts a CI run, so a pass costs one extra CI cycle before `ready-to-merge`. The board must say what 🧪 waits on.
- **Repository growth.** PNGs land in the PR branch and then on `main`. M14 limits them to two per round and optimises them; a plan rejected three times still adds six images.
- **URL encoding.** Plan folders contain emoji, spaces and `→`; a link not encoded byte for byte shows a broken image.
- **MCP surface in the adapter.** `--strict-mcp-config` exists to keep the operator's setup out of agents (`claude.rb:45-52`). The new key must add only the named server, and a spec must prove argv is unchanged for every other agent.
- **A browser on the build machine.** Headless Chrome is a heavy dependency; a machine without it fails every web verification. The failure must be one line on the board, not a stack trace.
- **Flaky verification.** A step that passes on retry would reject a good PR and spend the cap. M1 allows no retry.

## Conclusion

When this ships, an approved plan moves to 🧪 Verifying instead of stopping at 👀. The engine starts its app, launches headless Chrome for web apps, and hands both to `chewie-verifier`, which follows `## How to test` and leaves screenshots and a report in the plan folder. The engine commits the screenshots, then either rejects the PR with a comment and a linked PNG and sends it to 🔴, or waits for green CI and the coverage gate and applies `ready-to-merge`. In agent mode it merges the PR itself once `main` is green and the merge is clean; in human mode it waits for the human. Rejections are counted, and at the cap the plan waits for the arbitrator that plan 015 adds.

## Research

Gathered 2026-10-14. Repository claims cite `file:line` on `origin/main` (b2b5176) unless they name a branch. PR #26 (plan 005) is read from `origin/kig/005.00-review-state-labels`; plans 012 and 013 have no pushed code, so their interfaces come from `.plans/012.00-*/spec.md`, `.plans/012.00-*/plan-backend.md` and `.plans/013.00-*/spec.md` on `main`. Checks run: `bundle exec rspec` in this worktree, `2214 examples, 0 failures`, coverage 98.63%.

### Method

- Two read-only sweeps: one over PR #26's diff, one over `lib/`, `agents/` and `spec/` on `main`. Then the 012 and 013 documents, decisions M1–M15, and the installed `chrome-devtools-mcp` plugin source.
- Nothing was searched on the web: every question below was answerable from the repository or the local machine.

### Where verification sits today: nowhere

- **No code after review.** hansolo's approved verdict ends the plan's run with the folder still at 👀: `lib/openlanes/engine/dispatcher.rb:1090-1093` adds it to `@finished_plans` with "approved, awaiting merge". On the 005 branch the same block is at `dispatcher.rb:1147-1150`.
- **No state for it.** `in_review` (👀) is followed only by `approve` → ✅, `request_changes` → 🔴 and `slop` → 🚫 (`lib/openlanes/plans/state_machine.rb:181-191`). `approved` requires every PR merged (`lib/openlanes/plans/status.rb:251-263`). No agent handles `approved` or later (`state_machine.rb:98-111`, `SETTLED`).
- **No agent.** `agents/` holds nine files; none is `chewie-verifier`. `rg -n "chewie|ready-to-merge" lib agents spec` finds nothing on `main`.
- **hansolo's hand-off says a human merges.** `agents/hansolo-reviewer.md:58`: "`approved` | stays 👀; the run ends | a human merges. No agent merges."

### What PR #26 (plan 005) gives this plan

- **Labels.** `ReviewLabel = Data.define(:name, :colour, :meaning, :passing)` with `ALL` in M3 order (`lib/openlanes/plans/review_label.rb:11-29`, 005 branch). `ready-to-merge` is `1a7f37`, passing, "chewie verified it" (:28). Constants exist for `INITIAL` (:32) and `REJECTED` (:35), not for `ready-to-merge`. `ReviewLabel.passing` (:42), `fetch` (:47-50).
- **Applying a label.** `Vcs::Review#call(pr:, label:, dry_run: false)` (`lib/openlanes/vcs/review.rb:28-47`, 005) reads current labels, reads CI through `CiGate.verdict(@github.checks(...))`, refuses a passing label while CI is `:red` or `:pending` (:56-63), else swaps the label. Facade `Vcs.review` (`lib/openlanes/vcs.rb:21`, 005). CLI: `openlanes review PULL_REQUEST LABEL [-n]` (`lib/openlanes/cli/review/review.rb:13-19`, exit 1 on refusal, 64 on an unknown label).
- **CI.** `CiGate.verdict(checks)` returns `:none`, `:red`, `:pending` or `:green` (`lib/openlanes/vcs/ci_gate.rb:18-28`, 005) from `GitHub#checks(number:, repo:)`, which runs `gh pr checks N --json name,state,bucket` (`github.rb:230-246`, 005). PR CI only: nothing reads `main`'s CI.
- **GitHub seam.** New on 005: `ensure_label`, `swap_label`, `labels`, `checks`, `review_comments` (`github.rb:176-249`). Still missing: merge, mergeability (`mergeable`, `mergeStateStatus`), posting a comment, and any commit-status read.
- **The watch.** `Engine::PrWatch` polls every 15 s (`pr_watch.rb:23`, 005), first poll after one full interval (:31-35), one `pulls(state: "all")` per poll. Outcomes `:rejected`, `:merged`, `:closed`, `:waiting` (:13-15); `:rejected` only when the PR carries `review-rejected` (:69-80). `PrOutcomes` moves to 🔴 and mails the comments to every agent that handles 🔴 (`pr_outcomes.rb:53-63`, :136-142), to ✅ on merge (:67-75), to ❌ on close (:79-100). It is built only when `Config.current.human_merges?` and the engine stays up (`lib/openlanes/cli/run/run.rb:204`, 005). In `merge.by: auto` nothing watches and nothing merges (005 `spec.md:171`).
- **Config.** `merge.by` with `MERGERS = %i[human auto]`, default human (`lib/openlanes/support/config.rb:60-64`, :102, 005). The `merge:` parser accepts only `by` and rejects any other key (:214-226). `max_rejections` and `build_quality` do not exist.
- **`## How to test`.** `Lifecycle::Completion::HOW_TO_TEST = "## How to test"` (`completion.rb:15`, 005); the publisher writes it into the PR body (`publisher.rb:274`, 005) and refuses to publish without it (:283). `Publisher#label_for_review(url, resubmitted:)` removes every review label on a resubmit, `ready-to-merge` included (:309).
- **hansolo on 005.** `may: [gh pr comment]` (`agents/hansolo-reviewer.md:13`, 005); it applies its own labels through `openlanes review` and never applies `review-passed` (:23-25, :42-47). Its Next table still says a human merges (:62).
- **005 hands three things to this plan explicitly**: applying `ready-to-merge` (`spec.md:18`, :148, :170), auto-merge behaviour (:171), and the label names as an interface (`plan.md:76`).

### What plan 012 (app runner) gives this plan

- Namespace `OpenLanes::Apps`, facade `Apps.definition(config)`, `Apps.supervisor(...)`, `Apps.registry` (`.plans/012.00-*/plan-backend.md:3`, :11).
- `Supervisor.new(definition:, root:, plan:, branch:, registry:, publisher:, ...)`, `#start` (raises `Supervisor::StartFailed` with a reason), `#stop`, `#statuses`, `#preview` (`plan-backend.md:94-95`). Ports from the machine-wide registry, 11100–11999 (:62-65).
- Status wire shape with `url` and `framing` per process (`plan-backend.md:21-33`).
- **Left to this plan:** starting the app automatically on a state transition (`plan-backend.md:126`); the browser, `## How to test` and the verdict (012 `spec.md:47`); mirroring the headless browser into the Preview tab, "the tab's image area and SSE event type are left to that plan" (012 `spec.md:72`).
- **Gap:** 012 captures no process output. M1 wants "the last 20 lines of its log" when the app does not start. `Execution::Child.spawn` already merges stdout and stderr into one pipe (`lib/openlanes/execution/child.rb:48-55`) read by `each_chunk` (:123), so a tail is cheap, but no 012 unit owns it.

### What plan 013 (coverage gate) gives this plan

- The gate "withholds `ready-to-merge`" below `minimum` or on a missing report (013 `spec.md:37`, item 8 at :59) and runs in a clean PR checkout (:60).
- **013 leaves the call site open:** "No code applies `ready-to-merge` today … the wiring may need a plan of its own. This is the largest risk" (013 `spec.md:90`, :96). This plan is that wiring: the gate must be consulted before `ready-to-merge` is applied.
- `bin/coverage-changed` (PR #27, `origin/kig/004.00-web-control-room:bin/coverage-changed`) gates per-file coverage of `lib/` changes in this repository's own CI. It is not the M15 project gate, and plan 014 does not call it; it matters only because this plan's own `lib/` changes must pass it.

### The autonomy boundary and screenshots

- **An agent cannot commit.** `git commit` is in `FORBIDDEN_COMMANDS` (`lib/openlanes/execution/executor.rb:324-329`), and even granted through `may:` the after-check fails any run whose HEAD moved (`executor.rb:839-846`). `git push` and `gh pr merge` are `UNGRANTABLE` (:338; `granted_to` :641).
- **The engine commits, and only on the way to 🟢.** `Dispatcher#publish_for_review` returns early unless `target == :ready_for_review` (`dispatcher.rb:1199-1202`). `Publisher#publish` refuses a clean checkout (`publisher.rb:88-90`), then carries the plan folder, commits with `git add -A`, pushes, and opens a PR only if none is open (:94-105, :228-237).
- **The plan folder has one writer.** Agents are pointed at the plan folder in the main checkout (`lib/openlanes/execution/prompt.rb:62`, :134), and `carry_plan` replaces every copy of the plan in the worktree with the main checkout's (`publisher.rb:141-171`). PNGs written into the main checkout's `verification/<round>/` are therefore carried into the PR branch by the existing mechanism; PNGs written anywhere in the worktree's `.plans` would be deleted by it.
- **Comment links need the SHA first.** M14 links screenshots by commit SHA. The commit exists only after the engine pushes, so the comment can only be posted after the engine's push, never by the agent during its run.
- **A push restarts CI.** Committing screenshots to the PR branch starts a new CI run; `Vcs::Review` refuses `ready-to-merge` while CI is `:pending` (`review.rb:56-63`, 005). The pass path must push first, wait for green, and only then label.

### Browser automation

| Option | On this machine | Fit |
| --- | --- | --- |
| Chrome DevTools MCP | Plugin `chrome-devtools-mcp` 0.19.0 cached at `~/.claude/plugins/cache/chrome-devtools-plugins/chrome-devtools-mcp/latest/package.json:3`; Google Chrome in `/Applications` | Built for agents: `navigate_page`, `click`, `fill`, `take_screenshot` (`src/tools/pages.ts:133`, `input.ts:45`, :220, `screenshot.ts:14`). `take_screenshot` defaults to PNG and takes a `filePath` (`screenshot.ts:22-25`, :46). `--browserUrl` attaches to a running Chrome (`src/bin/chrome-devtools-mcp-cli-options.ts:24-28`); `--headless` and `--isolated` exist (:90-105). |
| Playwright | Not installed: `npx --no-install playwright --version` fails, `~/Library/Caches/ms-playwright` absent | The agent would write and run scripts; browsers need a download. |
| Cypress | 14.5.4 is a dev dependency of `web/` (`web/package.json:55`); binaries 14.5.4, 15.21.1, 16.1.1 cached under `~/Library/Caches/Cypress` | A test runner for openlanes' own UI. Driving an arbitrary app step by step means writing a spec file per step list. Wrong shape. |

- **Blocker for MCP:** the claude adapter launches every agent with `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` (`lib/openlanes/adapters/claude.rb:50-52`), so no agent can reach any MCP server today. An agent-specific MCP config needs a new frontmatter key and an adapter change. The registry parses a fixed set of keys (`lib/openlanes/agents/registry.rb:96-118`) and only the claude adapter has this flag.
- **Mirroring (M13):** if the engine launches headless Chrome itself with a remote-debugging port and points the MCP server at it with `--browserUrl`, the engine holds a CDP connection of its own and can capture a frame every 2 s for the Preview tab, independent of the agent. 012's research recommends the 2-second poll over screencast (012 `spec.md:145-149`).
- **PNG optimisation:** `vips` and `magick` are both at `/opt/homebrew/bin`. M14 names either.

### The merge checks

- **PR CI:** `CiGate.verdict` (005) as above.
- **`main`'s CI:** this repository runs CircleCI (`.circleci/config.yml`), so `gh run list` (Actions only) would see nothing. CircleCI reports to GitHub as commit statuses or check runs on the commit, so `main`'s verdict means reading both for `main`'s HEAD SHA (`gh api repos/{repo}/commits/{sha}/status` and `.../check-runs`). Neither call exists in `GitHub`.
- **Clean merge:** `gh pr view N --json mergeable,mergeStateStatus` (`MERGEABLE`, `CLEAN`). Not in `GitHub`'s `VIEW_FIELDS` (`github.rb:82`).
- **Merge method:** this repository's history merges with merge commits ("Merge pull request #25 …", `git log --oneline -3 origin/main`). No decision names a method.
- **15-second poll:** exists for human mode (005). In agent mode nothing polls; the merge step needs the same cadence.

### Rejections

- Nothing counts them. hansolo counts its own from the ledger and signs `rejected 1/2` or `2/2` by prose (`agents/hansolo-reviewer.md:40-42`). The engine reads verdicts by substring of the signed note (`dispatcher.rb:1161-1178`, `verdict_of`, `target_for`).
- M6 counts hansolo's and chewie's rejections together against `merge.max_rejections`, defaulting from M5's `build_quality` table (3/2/2/1). Neither key exists (above).
- The arbitrator is plan 015, which depends on this plan (`.plans/015.00-*/spec.md:2`). This plan can detect the cap but has no arbitrator to call.

### Adding a state touches derived tables

Per `CLAUDE.md` "When adding a state": `STATUSES`, an `aasm` event, `agents/*.md` `handles:`, and `lib/openlanes/linear/mapping.rb` (asserted by `spec/openlanes/linear/mapping_spec.rb:11-17`). Also the control room's stations (`lib/openlanes/live/stations.rb:38-41`) and an eval case for every agent that handles a state (`spec/openlanes/evals/corpus_spec.rb:14`).

### Findings, Conclusion & References

**Answers to "What research needs to settle"**

1. **Browser:** Chrome DevTools MCP against an engine-launched headless Chrome. It is the only option built for an agent to drive step by step, it saves PNG directly, and the engine-owned Chrome gives M13 mirroring for free. Cost: a per-agent MCP config in the claude adapter.
2. **PNG and committing:** the MCP tool writes PNG; the engine optimises with `vips` (fallback `magick`) and commits through the publisher's carry-commit-push path, extended beyond `:ready_for_review`. The agent writes PNGs into the main checkout's plan folder, never the worktree.
3. **Merge checks and the poll:** PR CI via `CiGate` (005), `main`'s CI via commit status plus check runs on `main`'s HEAD (new), mergeability via `gh pr view` (new), merge via a new `GitHub#merge` called only from engine code. The 15-second `PrWatch` from 005 covers human mode; agent mode needs the same cadence.

**Contradictions**

1. `executor.rb:16-20` and `CLAUDE.md` ("The autonomy boundary") say the after-check also verifies "no new remote ref appeared". The code compares HEAD only (`executor.rb:839-846`). Production runs the HEAD check; `git push` being `UNGRANTABLE` is the real guard.
2. M1 says chewie applies `ready-to-merge`, but the screenshot push leaves CI pending and `Vcs::Review` refuses a passing label while pending. Production (005) would refuse it.
3. M14 links screenshots "by commit SHA", which only the engine can produce, while M1 says chewie comments. The comment must come from the engine.
4. The spec stub's `depends_on: ["005", "012", "013"]` was not `NNN.MM`; corrected to `"005.00"` and so on. The stub's body headings were duplicated, empty, after `## How to tell it's working?`; removed.
5. `hansolo-reviewer.md:58` (main) and :62 (005) say a human merges; M2 says the engine merges in agent mode.
6. 005 `spec.md:15` gives `review-passed` as `0b6e2e`; its code uses `1d76db` (`review_label.rb:22-25`, 005). Not this plan's label, noted only.

**Could not settle** (for yoda)

1. Whether verification is a new folder state or a label phase inside 👀.
2. Who applies labels and comments: chewie through `openlanes review`, or the engine from chewie's signed verdict.
3. Where the rejection cap goes before plan 015 exists.
4. Default `max_rejections` with no `build_quality` key.
5. Merge method (merge commit, squash, rebase) and branch deletion.
6. What chewie does in a project with no `app:` block.
7. A merge conflict at merge time: back to 🔴, or to the human.
8. How `chrome-devtools-mcp` is installed and pinned, since an agent run should not download packages.
9. Whether non-claude adapters (codex, pi) can run chewie.

**Sources**

- Repository, `origin/main` b2b5176 and `origin/kig/005.00-review-state-labels`, cited inline.
- `chrome-devtools-mcp` 0.19.0 source in the local plugin cache (ChromeDevTools/chrome-devtools-mcp, Apache-2.0 per its repository). Cited, not copied.
- No web sources, no paywalled or licensed sources.
