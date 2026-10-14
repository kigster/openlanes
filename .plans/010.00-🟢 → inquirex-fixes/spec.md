---
depends_on: []
---

# Inquirex Fixes

## What we are trying to achieve

Fix the inquirex gems in `/Users/kig/github/inquirex` so openlanes can depend on them.

## Why it matters

`lanes init` interviews through inquirex-tty (decision M16), and the published gems cannot be used as they are.

## What already exists

- Decision M17 in `docs/decisions/decisions-on-merge-modes-and-verification.md`, which lists the five problems.
- The gems' own specs and CI (Ruby 4.0.2 only).

## What research needs to settle

- The shape of `Engine#back`, and the key that reaches the program in iTerm and Terminal.app (Cmd-Backspace may not).
- A non-interactive mode: an answers file, `--yes`, results on stdout or `-o`.
- Whether the gems pass their suites on Ruby 4.1.0-preview1.

## How to tell it's working?

- `inquirex`, `inquirex-llm` and `inquirex-tty` at the new versions install together in one bundle.
- A flow can be run with preset answers and no TTY, and its results land on stdout.
- Going back during a TTY run returns to the previous question with its answer filled in.
- No real name or email appears in any README.

> [!NOTE]
>
> [2026-10-13 07:04:16 PM PDT] [ agent: leah-researcher   status: **Interrupted, round 1 (harness died)** ]

## Research

Scope: `inquirex`, `inquirex-llm`, `inquirex-tty`, all at 0.10.0 in `/Users/kig/github/inquirex`. Read-only: nothing in the gems was changed. Test runs used a scratch copy of `inquirex-tty`.

### Answers

1. **`Engine#back`: shape.** No `back` exists (`rg` for back/undo/previous across the three libs finds none). `history` holds step ids only (`inquirex/lib/inquirex/engine.rb:65`, appended in `advance_step`, `:384`). Popping it alone leaves `answers`, `totals` (accumulators and the `:text` transcript), `skipped` and `suggestions` stale. Replaying from scratch fails too: Proc defaults and `prefill!` extractions do not re-derive. Recommended: push `to_state` (`engine.rb:270`) before each `answer`, `skip` and `advance`; `back` restores the last snapshot whose `current_step_id` is a collecting step, through the existing `restore_state` (`engine.rb:316`).
2. **Back key in TTY.** Not settled (see below). Facts:
   - `tty-reader` 0.9.0 maps Ctrl-B to `:ctrl_b` (`tty-reader-0.9.0/lib/tty/reader/keys.rb:10`). `tty-prompt` 0.23.1 binds no `ctrl_b` (`rg` over its `lib`).
   - Cmd-Backspace has no shipped default that I could find. Users map it by hand to `0x15` (Ctrl-U) in iTerm2 ([iTerm2 key docs](https://iterm2.com/documentation-preferences-profiles-keys.html), retrieved 2026-10-13; the Ctrl-U mapping is in a [search result](https://blog.mariusschulz.com/blog/keyboard-shortcuts-for-jumping-and-deleting-in-iterm2), not opened). No source found for Terminal.app.
   - `tty-prompt` 0.23.1 exposes no key hook I could find, so a back key needs a design: a subclassed prompt, or a raise from the keypress handler.
3. **Non-interactive mode.** None exists. `run.rb` takes only `flow_file` and `-o` (`inquirex-tty/lib/inquirex/tty/commands/run.rb:12`), and writes JSON to stderr (`:25`).
   - `-o` already means "file". M17's "stdout" needs `-o -`, per the CLI convention.
   - Answers must reach the engine through `answer` and `skip`, not `prefill!`. `prefill!` stores a multi-select as a suggestion that never satisfies `skip_if` (`engine.rb`, `prefill_suggestion`), so the run would stop at that question with no TTY.
   - `Renderer` cannot be reused headless: display steps call `prompt.keypress` (`renderer.rb:104-135`).
   - `--yes` must take each step's default, and fail (non-zero) on a required step with no answer. It must never prompt.
4. **Ruby 4.1.0-preview1.**
   - `inquirex`: `bundle exec rspec`, 946 examples, 0 failures (97.37% line coverage).
   - `inquirex-llm`: 235 examples, 0 failures (98.39%).
   - `inquirex-tty`: 120 examples, 0 failures on Ruby 4.0.6 with its pinned 0.9.5 deps. On 4.1.0-preview1 `bundle install` fails before any spec runs: `NameError: uninitialized constant Pathname::SEPARATOR_PAT` in bundler 4.0.10, `source/path.rb:223`. That is the Bundler build on Ruby 4.1, not the gem's code.

### Contradictions

- **Install conflict (M17.1), confirmed.** `inquirex-tty.gemspec:37-38` requires `inquirex ~> 0.9.5` and `inquirex-llm ~> 0.9.5`. Both are at 0.10.0 (`inquirex/lib/inquirex/version.rb:4`, `inquirex-llm/lib/inquirex/llm/version.rb:5`). `inquirex-tty/Gemfile` (`INQUIREX_VERSION`) and `Gemfile.lock:25,27` pin 0.9.5 too.
- **Model ids (M17.2), confirmed.** `inquirex-llm/lib/inquirex/llm/anthropic_adapter.rb:29` defaults to `claude-sonnet-4-20250514`; `:40-42` maps the aliases to 4.x ids. The environment lists Claude 5.5 ids. Whether the API accepts them: not tested, no live call made.
- **README vs code.** `inquirex-tty/README.md:66` says answers go "to stdout"; the code writes stderr (`run.rb:25`). README `:78` agrees with the code.
- **Real names in READMEs (M17.4), confirmed.** `inquirex-tty/README.md:97-98` and `:217-220` carry a real name and a real email as sample answers. `inquirex-llm/README.md:419` and `inquirex/README.md:792` carry a real name in copyright lines. The owner decides whether copyright lines count.
- **No `back` (M17.5), confirmed.** See answer 1.
- **Which pins production runs:** not settled. I did not inspect openlanes' own `Gemfile`.

### Not settled

1. Which key delivers back in iTerm2 and Terminal.app. Needs a person to press keys with `cat -v` in each. Candidate if Cmd-Backspace fails: Ctrl-B.
2. How a `tty-prompt` `select` or `ask` is interrupted by the back key.
3. Whether `inquirex-tty`'s specs pass on 4.1.0-preview1 without Bundler.
4. Whether the Claude 5.5 model ids are accepted by the API. Needs a live key.
5. Which inquirex version openlanes pins.
6. Answers-file format (JSON or YAML), and what `--yes` does with an LLM step. Product choice.

### Findings, Conclusion & References

Conclusion: the install conflict is a pin fix in `inquirex-tty` (gemspec, Gemfile, lock). Back is a snapshot stack in `inquirex` core. Non-interactive mode does not exist and needs designing. The core two gems pass on Ruby 4.1.0-preview1; the TTY gem is verified on 4.0.6 only.

References (retrieved 2026-10-13):
- iTerm2 key mapping docs: https://iterm2.com/documentation-preferences-profiles-keys.html
- Ctrl-U mapping for Cmd-Backspace, search result: https://blog.mariusschulz.com/blog/keyboard-shortcuts-for-jumping-and-deleting-in-iterm2
- Reported Cmd+Delete sending 0x15 in iTerm2, search result: https://claudeissues.com/issue/38974-bug-iterm2-cmd-delete-prints-literal-0x15-instead-of-killing-line-regression-in

## Framings

1. **Five bug fixes.** Each of M17.1-5 is a ticket against one gem. Cheap, but "back" and "non-interactive" are features, and the list hides their design.
1. **A contract for `lanes init`.** What openlanes (decision M16, plan 011) needs from the gems: install together, ask with an LLM extractor, go back, run headless in tests and CI. Each fix is judged by whether `lanes init` can rely on it.

Chosen: 2. It orders the work by what 011.00 blocks on, and it explains why the Ruby 4.1 and model-id items are checks rather than features.

## Goal

After this plan, `inquirex`, `inquirex-llm` and `inquirex-tty` are released at one new version that installs in a single bundle; a flow can be run with preset answers and no TTY, with results on stdout; a TTY run can step back to the previous question with its answer filled in; and no README carries a real name or email. Plan 011.00 can then build `lanes init` on them.

## Non-Goals

- No new flow DSL features, step types or verbs beyond `back` and the headless runner.
- No web or JS widget (M16 v2.0); the web back button already exists.
- No change to openlanes itself. Adopting the new versions in its `Gemfile` belongs to 011.00.
- No new LLM adapters, and no live-API test suite.
- No Ruby version matrix beyond what the research ran (4.0.x and 4.1.0-preview1).
- No rewrite of the `Renderer` beyond what back needs.

## In scope

Repository for all items: `/Users/kig/github/inquirex`.

1. **Version alignment (M17.1).** `inquirex-tty.gemspec:37-38`, `inquirex-tty/Gemfile` and `Gemfile.lock` accept `inquirex` and `inquirex-llm` 0.10.x or the new version. *Check:* `bundle install` of all three at the new versions in a scratch Gemfile succeeds, and `bundle exec rspec` passes in each gem.
1. **Model ids (M17.2).** `anthropic_adapter.rb:29` default and the aliases at `:40-42` name current Claude ids, and the id list is one constant. *Check:* a spec asserts the default and every alias value is in that list; no `claude-sonnet-4-20250514` remains (`rg`).
1. **`Engine#back` (M17.5).** Snapshot `to_state` before each `answer`, `skip` and `advance`; `back` restores the last snapshot whose step collects an answer, via `restore_state`. *Check:* specs show that after `back`, `answers`, `totals` (including `:text`), `skipped`, `suggestions` and `history` equal their values before the undone step; `back` at the first step is a defined no-op or error (see open question 7).
1. **Back in the TTY run.** A key chosen per open question 1 returns to the previous question with its answer pre-filled as the default. *Check:* a spec drives the renderer with a fake prompt that emits the back key, and the engine ends on the previous step with its answer as default.
1. **Headless run.** `inquirex-tty run FLOW --answers FILE` (and `--yes`) runs without a TTY, feeding `answer` and `skip` (not `prefill!`). *Check:* a spec runs a flow with a multi-select under a closed STDIN and gets all answers; `--yes` takes each step's default and exits non-zero naming the step when a required one has none; neither ever calls the prompt.
1. **Results channel (M17.3).** Results go to stdout by default; `-o FILE` writes a file, `-o -` is stdout. Interactive rendering stays on stderr. README `:66` and `:78` agree with the code. *Check:* a spec captures stdout and stderr separately, and parses stdout as JSON.
1. **No real names or emails (M17.4).** Replace the sample answers at `inquirex-tty/README.md:97-98` and `:217-220` with fictional ones, e.g. `Ada Example` / `ada@example.com`. *Check:* `rg` for the owner's name and email across the three repos' READMEs returns nothing outside copyright lines (open question 4).
1. **Ruby 4.1.0-preview1.** `inquirex` and `inquirex-llm` stay green (research: 946 and 235 examples, 0 failures). `inquirex-tty` is run without Bundler's path source on 4.1.0-preview1. *Check:* the result is recorded in the plan's `plan.md` or the release notes, passing or as a documented Bundler-only failure.
1. **Release.** Bump the three versions together, with CHANGELOG entries. *Check:* each `version.rb` agrees, and the gemspec constraints reference it.

## Out of scope

- Publishing to rubygems.org: irreversible and outward-facing; a human does it.
- Verifying the Claude 5.5 ids against the live API: needs a key and spend; recorded as an open question.
- Fixing Bundler 4.0.10's `Pathname::SEPARATOR_PAT` failure on 4.1: it is not in the gems.
- Terminal.app/iTerm2 key configuration instructions beyond the README line naming the chosen key.
- Changing how openlanes picks the LLM adapter (M16 states it does).

## Back end / front end

`luke-backend` and `rey-frontend` build these as a pair. Here the "back end" is the `inquirex` engine and library surface; the "front end" is the terminal UI of `inquirex-tty`.

| Item                         | luke-backend (engine, libs)                        | rey-frontend (inquirex-tty UI) |
| :--------------------------- | :------------------------------------------------- | :----------------------------- |
| Version alignment            | gemspec and lock in all three                      | gemspec of inquirex-tty        |
| Model ids                    | `inquirex-llm` constant, aliases, spec             | none                           |
| `Engine#back`                | snapshot stack, `back`, specs                      | none                           |
| Back in TTY                  | exposes `back` and `can_back?`                     | key binding, pre-filled default, tip line |
| Headless run                 | answer feeding contract: `answer`/`skip`, defaults | `--answers`, `--yes`, run.rb   |
| Results channel              | none                                               | `run.rb`, README               |
| README names                 | none                                               | READMEs of all three           |
| Ruby 4.1 check, release      | version bump, CHANGELOGs                           | run tty specs, record result   |

## Open questions

1. **Back key.** Cmd-Backspace is not delivered by default (research, answer 2); Ctrl-B is mapped by `tty-reader` and unbound in `tty-prompt`. Assumed: Ctrl-B, with the tip line naming it, unless a human confirms Cmd-Backspace with `cat -v` in iTerm2 and Terminal.app. M16 says to pick a key that arrives.
1. **Interrupting a prompt.** How a `select` or `ask` is aborted by the key (subclass vs raise in the keypress handler) is unsettled; the implementer decides and records it.
1. **Answers-file format.** Assumed: JSON and YAML, chosen by extension, as `{step_id: value}`. Product choice, unconfirmed.
1. **Copyright lines.** `inquirex-llm/README.md:419`, `inquirex/README.md:792` carry a real name. Assumed: the owner's copyright line stays; only sample data changes. Owner to confirm.
1. **`--yes` with an LLM step.** Unsettled. Assumed: the step is skipped with its default and no adapter is called.
1. **Model ids.** The exact ids to default to, and whether the API accepts them, are untested.
1. **`back` at the first step.** Assumed: returns `false` and changes nothing.
1. **openlanes' pin.** Not inspected (research). Assumed the new version is pinned by 011.00.
1. **Version number.** Assumed 0.11.0 for all three (new features); owner to confirm.

## Risks to planning or execution

- Cmd-Backspace may never arrive; tip text and tests must follow whichever key ships.
- `back` must restore Proc-default and `prefill!`-derived state; replay does not (research, answer 1). A snapshot that skips a field is a silent bug, so the spec for it must compare whole `to_state` hashes.
- A headless `prefill!` path would hang on multi-selects (`skip_if` never satisfied); the test must include one.
- `inquirex-tty` cannot be bundled on 4.1.0-preview1, so green there is not provable by CI as set up (Ruby 4.0.2 only).
- Moving results from stderr to stdout changes behaviour for any caller reading stderr; none known, none searched outside the three gems.
- The work is in a repo outside this one; a worker needs an `alock` claim and a branch there.

## Conclusion

Three gems at one version install together. `Engine#back` restores a full prior state; the TTY gem binds a key to it and pre-fills the answer. `inquirex-tty run` accepts an answers file or `--yes`, never touches a TTY, and prints results to stdout (or `-o FILE`). Default model ids are current, README samples are fictional, and the Ruby 4.1.0-preview1 result is written down. Plan 011.00 is unblocked.
