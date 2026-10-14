---
depends_on: ["005.00", "012.00", "013.00"]
---

# Chewie Verifier

## What we are trying to achieve

`chewie-verifier` checks out a PR that passed review, starts the app, follows `## How to test`, and labels it `ok-to-merge` or rejects it with a PNG screenshot. In agent mode the engine then merges; rejections are capped.

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

- A PR whose steps pass gets `ok-to-merge`, and in agent mode merges once CI on the PR and on `main` is green.
- A PR whose steps fail gets `review-rejected`, a comment and a PNG screenshot, and the plan goes to 🔴.
- After `max_rejections` the arbitrator is called.

## Research

Gathered 2026-10-14. Repository claims cite `file:line` on `origin/main` (b2b5176) unless they name a branch. PR #26 (plan 005) is read from `origin/kig/005.00-review-state-labels`; plans 012 and 013 have no pushed code, so their interfaces come from `.plans/012.00-*/spec.md`, `.plans/012.00-*/plan-backend.md` and `.plans/013.00-*/spec.md` on `main`. Checks run: `bundle exec rspec` in this worktree, `2214 examples, 0 failures`, coverage 98.63%.

### Method

- Two read-only sweeps: one over PR #26's diff, one over `lib/`, `agents/` and `spec/` on `main`. Then the 012 and 013 documents, decisions M1–M15, and the installed `chrome-devtools-mcp` plugin source.
- Nothing was searched on the web: every question below was answerable from the repository or the local machine.

### Where verification sits today: nowhere

- **No code after review.** hansolo's approved verdict ends the plan's run with the folder still at 👀: `lib/openlanes/engine/dispatcher.rb:1090-1093` adds it to `@finished_plans` with "approved, awaiting merge". On the 005 branch the same block is at `dispatcher.rb:1147-1150`.
- **No state for it.** `in_review` (👀) is followed only by `approve` → ✅, `request_changes` → 🔴 and `slop` → 💩 (`lib/openlanes/plans/state_machine.rb:181-191`). `approved` requires every PR merged (`lib/openlanes/plans/status.rb:251-263`). No agent handles `approved` or later (`state_machine.rb:98-111`, `SETTLED`).
- **No agent.** `agents/` holds nine files; none is `chewie-verifier`. `rg -n "chewie|ok-to-merge" lib agents spec` finds nothing on `main`.
- **hansolo's hand-off says a human merges.** `agents/hansolo-reviewer.md:58`: "`approved` | stays 👀; the run ends | a human merges. No agent merges."

### What PR #26 (plan 005) gives this plan

- **Labels.** `ReviewLabel = Data.define(:name, :colour, :meaning, :passing)` with `ALL` in M3 order (`lib/openlanes/plans/review_label.rb:11-29`, 005 branch). `ok-to-merge` is `1a7f37`, passing, "chewie verified it" (:28). Constants exist for `INITIAL` (:32) and `REJECTED` (:35), not for `ok-to-merge`. `ReviewLabel.passing` (:42), `fetch` (:47-50).
- **Applying a label.** `Vcs::Review#call(pr:, label:, dry_run: false)` (`lib/openlanes/vcs/review.rb:28-47`, 005) reads current labels, reads CI through `CiGate.verdict(@github.checks(...))`, refuses a passing label while CI is `:red` or `:pending` (:56-63), else swaps the label. Facade `Vcs.review` (`lib/openlanes/vcs.rb:21`, 005). CLI: `openlanes review PULL_REQUEST LABEL [-n]` (`lib/openlanes/cli/review/review.rb:13-19`, exit 1 on refusal, 64 on an unknown label).
- **CI.** `CiGate.verdict(checks)` returns `:none`, `:red`, `:pending` or `:green` (`lib/openlanes/vcs/ci_gate.rb:18-28`, 005) from `GitHub#checks(number:, repo:)`, which runs `gh pr checks N --json name,state,bucket` (`github.rb:230-246`, 005). PR CI only: nothing reads `main`'s CI.
- **GitHub seam.** New on 005: `ensure_label`, `swap_label`, `labels`, `checks`, `review_comments` (`github.rb:176-249`). Still missing: merge, mergeability (`mergeable`, `mergeStateStatus`), posting a comment, and any commit-status read.
- **The watch.** `Engine::PrWatch` polls every 15 s (`pr_watch.rb:23`, 005), first poll after one full interval (:31-35), one `pulls(state: "all")` per poll. Outcomes `:rejected`, `:merged`, `:closed`, `:waiting` (:13-15); `:rejected` only when the PR carries `review-rejected` (:69-80). `PrOutcomes` moves to 🔴 and mails the comments to every agent that handles 🔴 (`pr_outcomes.rb:53-63`, :136-142), to ✅ on merge (:67-75), to ❌ on close (:79-100). It is built only when `Config.current.human_merges?` and the engine stays up (`lib/openlanes/cli/run/run.rb:204`, 005). In `merge.by: auto` nothing watches and nothing merges (005 `spec.md:171`).
- **Config.** `merge.by` with `MERGERS = %i[human auto]`, default human (`lib/openlanes/support/config.rb:60-64`, :102, 005). The `merge:` parser accepts only `by` and rejects any other key (:214-226). `max_rejections` and `build_quality` do not exist.
- **`## How to test`.** `Lifecycle::Completion::HOW_TO_TEST = "## How to test"` (`completion.rb:15`, 005); the publisher writes it into the PR body (`publisher.rb:274`, 005) and refuses to publish without it (:283). `Publisher#label_for_review(url, resubmitted:)` removes every review label on a resubmit, `ok-to-merge` included (:309).
- **hansolo on 005.** `may: [gh pr comment]` (`agents/hansolo-reviewer.md:13`, 005); it applies its own labels through `openlanes review` and never applies `review-passed` (:23-25, :42-47). Its Next table still says a human merges (:62).
- **005 hands three things to this plan explicitly**: applying `ok-to-merge` (`spec.md:18`, :148, :170), auto-merge behaviour (:171), and the label names as an interface (`plan.md:76`).

### What plan 012 (app runner) gives this plan

- Namespace `OpenLanes::Apps`, facade `Apps.definition(config)`, `Apps.supervisor(...)`, `Apps.registry` (`.plans/012.00-*/plan-backend.md:3`, :11).
- `Supervisor.new(definition:, root:, plan:, branch:, registry:, publisher:, ...)`, `#start` (raises `Supervisor::StartFailed` with a reason), `#stop`, `#statuses`, `#preview` (`plan-backend.md:94-95`). Ports from the machine-wide registry, 11100–11999 (:62-65).
- Status wire shape with `url` and `framing` per process (`plan-backend.md:21-33`).
- **Left to this plan:** starting the app automatically on a state transition (`plan-backend.md:126`); the browser, `## How to test` and the verdict (012 `spec.md:47`); mirroring the headless browser into the Preview tab, "the tab's image area and SSE event type are left to that plan" (012 `spec.md:72`).
- **Gap:** 012 captures no process output. M1 wants "the last 20 lines of its log" when the app does not start. `Execution::Child.spawn` already merges stdout and stderr into one pipe (`lib/openlanes/execution/child.rb:48-55`) read by `each_chunk` (:123), so a tail is cheap, but no 012 unit owns it.

### What plan 013 (coverage gate) gives this plan

- The gate "withholds `ok-to-merge`" below `minimum` or on a missing report (013 `spec.md:37`, item 8 at :59) and runs in a clean PR checkout (:60).
- **013 leaves the call site open:** "No code applies `ok-to-merge` today … the wiring may need a plan of its own. This is the largest risk" (013 `spec.md:90`, :96). This plan is that wiring: the gate must be consulted before `ok-to-merge` is applied.
- `bin/coverage-changed` (PR #27, `origin/kig/004.00-web-control-room:bin/coverage-changed`) gates per-file coverage of `lib/` changes in this repository's own CI. It is not the M15 project gate, and plan 014 does not call it; it matters only because this plan's own `lib/` changes must pass it.

### The autonomy boundary and screenshots

- **An agent cannot commit.** `git commit` is in `FORBIDDEN_COMMANDS` (`lib/openlanes/execution/executor.rb:324-329`), and even granted through `may:` the after-check fails any run whose HEAD moved (`executor.rb:839-846`). `git push` and `gh pr merge` are `UNGRANTABLE` (:338; `granted_to` :641).
- **The engine commits, and only on the way to 🟢.** `Dispatcher#publish_for_review` returns early unless `target == :ready_for_review` (`dispatcher.rb:1199-1202`). `Publisher#publish` refuses a clean checkout (`publisher.rb:88-90`), then carries the plan folder, commits with `git add -A`, pushes, and opens a PR only if none is open (:94-105, :228-237).
- **The plan folder has one writer.** Agents are pointed at the plan folder in the main checkout (`lib/openlanes/execution/prompt.rb:62`, :134), and `carry_plan` replaces every copy of the plan in the worktree with the main checkout's (`publisher.rb:141-171`). PNGs written into the main checkout's `verification/<round>/` are therefore carried into the PR branch by the existing mechanism; PNGs written anywhere in the worktree's `.plans` would be deleted by it.
- **Comment links need the SHA first.** M14 links screenshots by commit SHA. The commit exists only after the engine pushes, so the comment can only be posted after the engine's push, never by the agent during its run.
- **A push restarts CI.** Committing screenshots to the PR branch starts a new CI run; `Vcs::Review` refuses `ok-to-merge` while CI is `:pending` (`review.rb:56-63`, 005). The pass path must push first, wait for green, and only then label.

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
2. M1 says chewie applies `ok-to-merge`, but the screenshot push leaves CI pending and `Vcs::Review` refuses a passing label while pending. Production (005) would refuse it.
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
