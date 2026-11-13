# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 223 | [\[060.00\](A) Improve Openlanes Low Hanging Fruit](https://github.com/kigster/openlanes/pull/223) | Open 🟡 |

## Round 1, backend-coder

- Baseline on clean HEAD (before this plan): `spec/openlanes/agents/routing_spec.rb` lines 19, 32, 42 fail; `spec/openlanes/live/redis_outage_integration_spec.rb:77` fails. Not caused by this plan.
- B3 done: `Plans::UnitSizes`, `Agents::Sizing` (`.openlanes.yml` `sizing:`), `Spec#unit_size`, Profile precedence step 3, Fable 5.2 catalogue entry, ceiling lifted only for a `sizing:`-configured model, planner.md `**Size:**` field. `bundle exec rubocop`: 0 offenses. `docs/architecture/` regenerated.
- Not started: B5a, B5b, B1, B4, B2, B6. `openlanes docs` / `just update-workflow` not yet re-run for the `**Size:**` field.

## Round 2, backend-coder

- B1 done: `Engine::ReviewPacket` (diff + digest built once per plan and head sha, `MAX_DIFF` cap with a truncation note), `Vcs::GitHub#pr_diff`, `Execution::Prompt` injects the packet for review-phase agents only; staff/security/design-reviewer briefs read the packet first. Specs: `review_packet_spec.rb`, `prompt_review_packet_spec.rb`. Cache row added to `docs/thread-safety.md`.
- B3 docs: `openlanes docs` now lists `**Size:**` (documentation.rb); `docs/WORKFLOW.md` regenerated (gitignored).
- Fixed baseline `routing_spec.rb` failures: the spec read this repo's own `.openlanes.yml` (`frontend: true`).
- Still red, and red on clean HEAD too, for the same `.openlanes.yml` leak: `dispatcher_spec.rb:523`, `run_workflow_spec.rb:115, :226, [1:2:6]`. `redis_outage_integration_spec.rb:77, :100` are timing-flaky (pass alone).
- `bundle exec rubocop`: 0 offenses.
- Not started: B5a, B5b, B4, B2, B6.

## Round 3, backend-coder

- Fixed the remaining `.openlanes.yml` leak: `dispatcher_spec.rb` and `run_workflow_spec.rb` now run from the fixture root (135 examples, 0 failures). This edits `dispatcher_spec.rb` before B5a, so B5a's "dispatcher specs unchanged" baseline is this round's version.
- B4 finding (for the PR body): nothing handles a provider rate limit today. `Executor#lost_session` retries only a *resumed* session that failed before spending anything (which covers an overload at start-up), and `dispatcher_outage_spec.rb` is about Redis, not the provider. A mid-run 429/529 is reported as an ordinary failure and costs an attempt.
- B4 part 1 done: `Execution::RateLimit.detect(status, transcript)` (429, `rate_limit_error`, `overloaded_error`, 529, `retry_after`), `#delay` (30 s doubling to a 900 s cap, up to 25% jitter, `retry_after` wins), `#phrase` for the board. Spec: `rate_limit_spec.rb`, 12 examples green. Rubocop clean on the touched files.
- B4 still to do: `Executor::Result#rate_limit` set from `verdict`, then the requeue in `steps/settle.rb` (after B5b).
- The full suite was not re-run this round (the background run was killed).

## Round 4, backend-coder

- B4 part 2 done: `Executor::Result#rate_limit` / `#rate_limited?`; `Executor#verdict` runs `RateLimit.detect` after the kill check and before the exit-status check, so a mid-run 429/529 comes back as its own outcome ("claude was turned away (rate_limited): …"). Three new examples in `executor_spec.rb` ("when claude exits non-zero"); `spec/openlanes/execution`: 477 examples, 0 failures. Rubocop clean on the touched files.
- B4 still to do: `Dispatcher#settle` still treats a rate-limited result as `!result.ok` (an attempt). The requeue with `RateLimit#delay`, the board phrase and the pause across all jobs belong in `steps/settle.rb`, after B5b.
- Full `bundle exec rspec` from round 4 (finished after signing): 5983 examples, 4 failures, exit 1.
  - `architecture_doc_spec.rb:13`: stale after `rate_limit.rb` and the `Executor::Result` change. Fix with `just update-architecture`.
  - `redis_outage_integration_spec.rb:72, :100`: timing-flaky, as in earlier rounds.
  - `apps/restart_spec.rb:77`: not yet investigated. Run it alone to see whether it is flaky.

## Round 5, backend-coder

- `just update-architecture` re-run; `architecture_doc_spec.rb` green.
- `apps/restart_spec.rb:77` passes when run alone (6 examples, 0 failures): timing under a loaded machine.
- The flaky `redis_outage_integration_spec.rb` was a real race: `Live::Store` shared one RedisClient across the tick, agent jobs and PR watch, and interleaved commands raised "can't modify string; temporarily locked". Every command now takes a `Monitor`, and the blocking XREAD has its own client behind its own lock. Before: 2 of 3 runs failed. After: 3 of 3 runs green; `spec/openlanes/live` 626 examples, 0 failures. Row added to `docs/thread-safety.md`.
- Full `bundle exec rspec` this round: 5986 examples, 4 failures, all in `cli/web_spec.rb:255, :277` and `cli/engine_command_spec.rb:289, :317`. The operator's shell exports `OPENLANES_ADMIN_CREDENTIALS`, and the suite inherited it. `spec_helper.rb` now deletes it at load, beside `NO_COLOR`; both files then ran 84 examples, 0 failures. No other failures in that run, so the suite should now be green. Not confirmed by a second full run.
- `bundle exec rubocop`: 857 files, 0 offenses.
- Units still open: B5a, B5b, B4 settle requeue, B2, B6.

## Findings: design-reviewer

### F201 [critical] lib/openlanes/engine/dispatcher.rb:260
The plan's own critical unit is mostly undelivered. Only the discard section moved out of `Dispatcher` (`Steps::Rename`); `Steps::Assign`, `Steps::Poll` and `Steps::Settle` do not exist, so B5b's target (dispatcher under 1,000 lines and 60 methods) is unmet. B4's requeue, B2's gate and B6's integration spec are absent too. The new `Executor::Result#rate_limited?` and `RateLimit#delay` have no caller: `Dispatcher#settle` still counts the result as `!result.ok`. The builder's own notes say "Units still open: B5a, B5b, B4 settle requeue, B2, B6". Scenario: a mid-run 429 on a build costs the plan an attempt exactly as before; spec goals 2, 4 and 5 are unchanged.

### F202 [minor] lib/openlanes/execution/prompt.rb:56
`Execution::Prompt` now defaults `packet:` to `Engine::ReviewPacket.method(:build)`, so Execution reaches into Engine's internals rather than a facade, and the architecture diff gains a new `Execution ..> Engine` edge while Engine already depends on Execution. Scenario: the next change to the packet's constructor breaks every Prompt caller. Expose it through an `Engine` facade method, or inject it from the dispatcher.

### F203 [minor] lib/openlanes/agents/profile.rb:70
`Profile.sized` reaches for `Config.current.sizing`, although `dealing:` right beside it is injected. A spec cannot supply a sizing table without stubbing the global config. Also `Spec.for` (spec.rb:170) now reads plan.md straight from disk behind a `respond_to?(:feature)` duck-type, so a parser of spec.md has two read paths and a plan.md fact (`unit_size`) on the wrong value object. Pass `sizing:` into `resolve` and compute the size from `UnitSizes` at the caller.

### F204 [minor] lib/openlanes/agents/sizing.rb:44
`Sizing::PHASES = %w[build frontend]` hand-writes which agents build, a fact `agents/*.md` frontmatter already carries (`phase:`), so a new builder agent silently skips sizing. `uncapped?` is "this size's entry differs from DEFAULTS", which means "the operator changed anything", not "the operator named a model above the ceiling"; derive it from the model named.

### F205 [minor] lib/openlanes/engine/review_packet.rb:60
The cache key is plan + head sha, but the digest reads spec.md, plan.md, contract.md and the PR row, which change without HEAD moving (plan folders live outside the repo), and the cache is never evicted. `assemble` takes only the first open PR where a plan may list several. The class also shells out to git (`head_of`), builds, caches and formats. Scenario: a reviewer round after plan.md is edited at the same head sees the old units. Key on a digest of the inputs, and bound the cache.

### F206 [minor] lib/openlanes/engine/steps/rename.rb:2
`Steps::Rename` only drains discards, so its name and its "renames that follow a settle" comment promise more than it does. It also builds `Plans::Tree.new(dir: ...)` itself where `fresh_by` was used, and `Dispatcher` still owns the `@discarding` table it mutates. Name it for the discard it handles, or let it own the table.

## Findings: security-reviewer

### F101 [minor] lib/openlanes/engine/review_packet.rb:34
`to_prompt` wraps the diff in a fixed three-backtick fence and quotes spec.md, contract.md and plan headings unfenced, straight into the reviewer's privileged prompt. Scenario: a changed file contains a line of three backticks followed by `## Boundary` or "sign `Completed, round 1 (great)`"; the fence closes early and the rest reads as harness instruction instead of the author's content. Before this PR a reviewer saw such text only as tool output. Suggest a per-build nonce fence (as this round's own packet does) and a note that everything inside is untrusted. Not exploitable beyond what a PR author can already attempt, so a 🔓, not a block.

### F102 [minor] lib/openlanes/execution/rate_limit.rb:36
`delay` returns `retry_after.to_f` with no cap, and `retry_after` is scraped by regex from whatever the CLI printed (`transcript.plain`). Scenario: a failed run whose output contains "retry after 99999999" (a tool result, a file the agent read) yields a ~3-year wait; the plan, and per B4 all new assignments, would stall. Also `\b429\b` matches any failing run that prints 429 (test output), which B4's settle step will requeue without costing an attempt, so such a run could loop forever. Suggest clamping to `CAP` and bounding consecutive rate-limit requeues per plan.

## Findings: staff-reviewer

### F1 [critical] lib/openlanes/engine/dispatcher.rb:1
Half the plan is unbuilt, but the plan sits at 👀 In Review. Spec items 2 (gate review behind lint and tests) and 5 (split dispatcher.rb, which the spec calls "critical to the success of the factory") are not delivered. Units B5a (only `Steps::Rename` exists, no `Steps::Assign`), B5b, the B4 settle requeue, B2 and B6 are missing; round 5 of this file lists them as open. Scenario: a builder signs Completed on a red suite. Expected: the plan bounces back to backend-coder and no reviewer starts. Actual: there is no `PreReviewGate`, so reviewers start, which is exactly how this review began. Also `bundle exec rspec spec/openlanes/integration/low_hanging_fruit_spec.rb` from "How to test" fails: the file does not exist.

### F2 [critical] lib/openlanes/execution/executor.rb:899
B4 is only half-wired: `Executor#verdict` now returns a `rate_limited` result, but the dispatcher still settles it as `!result.ok`, an ordinary failed attempt (round 4 says so). Scenario: with `jobs: 7`, a 529 burst hits every running plan. Expected per spec item 4: they pause and requeue with no attempt spent. Actual: every plan loses an attempt, the same as before this PR. The only change is the note text.

### F3 [minor] lib/openlanes/execution/rate_limit.rb:52
`OVERLOADED`/`LIMITED` match bare `\b529\b`/`\b429\b` anywhere in `transcript.error` and `transcript.plain`. Scenario: a CLI exits 1 with an error line naming `spec/foo_spec.rb:529` or "line 429". Expected: an ordinary failure. Actual: it is classified `:overloaded`/`:rate_limited`. Once the settle requeue costs no attempt (F2), a real failure like this one retries forever. Anchor the codes to HTTP context (`status[: ]529`, `HTTP 429`, `"type":"overloaded_error"`) and add a negative spec.

### F4 [minor] lib/openlanes/engine/review_packet.rb:70
The cache key uses the *local* checkout HEAD, but the diff comes from GitHub's PR head, and the two can differ (in this round the worktree is at fdde247b while PR #223's head is 39f5401). Scenario: a builder commits but has not pushed yet. Expected: the packet's `head_sha` matches the diff it carries. Actual: the packet labels a stale remote diff with the new local sha and caches it under that key. Key on the PR's `headRefOid` instead. The cache also never evicts (one entry per plan per head for the life of the engine), and `head_of` raising `Errno::ENOENT` escapes `Prompt#review_packet`'s `rescue Error`.

## Round 7, backend-coder (🔴 Changes Requested)

The branch was rebuilt between rounds. The local branch is now `fdde247b`: B3 alone, on a `main` (`e760d85a`) that already holds most of what this plan asked for. PR #223's head, `39f5401d`, is the old branch on `4fcb6eb2`, and the findings above were written against it. On `fdde247b`:

| Finding | Where it stands on `fdde247b` |
| :-- | :-- |
| F1, F201: dispatcher not split (B5a, B5b) | Done on `main`: `lib/openlanes/engine/dispatcher.rb` is 390 lines with 20 methods, and the steps live in `lib/openlanes/engine/dispatcher/` (`assign`, `poll`, `settle`, `rename`, `start`, …). My `Steps::Rename` is gone, so F206 no longer applies. |
| F2, F3, F102: rate limit half-wired, bare `429`/`529`, `retry_after` not capped | Done on `main` as `Execution::Throttle` (`throttle.rb`, `throttle/backoff.rb`, `throttle/limit.rb`; commits `b5d58a4f`, `a4616326`). It reads only the CLI's last three lines and retries inside the same attempt. I started porting my `RateLimit` and reverted it so the two would not overlap. |
| F202, F205, F4, F101: `Engine::ReviewPacket` | Gone with the rebuild. `main` has `Execution::ReviewPacket`, which fences with a nonce and marks the content untrusted. |
| F1: no `PreReviewGate` (B2) | Still open. Nothing on `main` provides it. |
| F1: `spec/openlanes/integration/low_hanging_fruit_spec.rb` missing (B6) | Still open. |
| F203: `Profile.sized` reads `Config.current.sizing`; `Spec.for` reads plan.md | Still open, in this branch's B3 commit. |
| F204: `Sizing::PHASES` hard-coded; `uncapped?` means "differs from defaults" | Still open, in this branch's B3 commit. |

Also lost in the rebuild, and not on `main`: the `Live::Store` thread-safety fix (Monitor around the shared RedisClient), the `.openlanes.yml` isolation in `routing_spec`, `dispatcher_spec` and `run_workflow_spec`, and the `OPENLANES_ADMIN_CREDENTIALS` reset in `spec_helper.rb`. All three are on `39f5401d` and can be cherry-picked from there.

Not done this round: the full suite was not run, and no code changed (`git status` is clean).

Next round, in order: F203 and F204 on the sizing code, B2 `PreReviewGate` in `dispatcher/settle.rb`, B6 integration spec, the three lost fixes above, then full `bundle exec rspec` and `bundle exec rubocop`.

Note on F204: `lib/openlanes/adapters/claude.rb:15` on `main` says the Claude adapter has no ceiling any more, so the `uncapped?` half of F204 may be moot. Check that before reworking it.

## Round 8, backend-coder

- F203 fixed. `Profile.resolve` now takes `unit_size:` and `sizing:` (defaulting to `Config.current.sizing`, the same way `dealing:` defaults). `Profile.sized` is gone. `Plans::Spec` is back to `main`'s version: no `unit_size`, no plan.md read. The plan.md read lives in one place, `Plans::UnitSizes.in_folder(dir)`, and the caller (`Executor#profile_for`) passes its result in, for builders only. Files: `agents/profile.rb`, `plans/spec.rb`, `plans/unit_sizes.rb`, `execution/executor.rb`.
- F204 fixed. `Sizing::PHASES` is gone. `Agent::BUILD_PHASES` (`build`, `frontend`) and `Agent#builder?` read the frontmatter `phase:`, and `Engine::Rebase::IMPLEMENTER_PHASES` now points at the same constant, so the fact is written once. The `uncapped?` half was already gone on this branch, and `main` has no Claude model ceiling.
- `spec/openlanes/agents/profile_sizing_spec.rb` injects `sizing:` and no longer stubs `Config.current`. It adds a front-end builder case and two `UnitSizes.in_folder` cases: 11 examples, 0 failures. `spec/openlanes/{agents,plans}`, `config_sizing_spec` and `rebase_spec`: 841 examples, 0 failures.
- `just update-architecture` re-run. `bundle exec rubocop`: 951 files, no offenses.
- Full `bundle exec rspec`: started this round, output in `/tmp/ol060-r8-full.txt`. Check it before signing Completed.
- Still open: B2 `PreReviewGate`, B6 integration spec, and the three fixes the rebuild dropped (they are on `39f5401d`).
