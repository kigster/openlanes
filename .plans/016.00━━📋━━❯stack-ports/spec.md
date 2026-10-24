---
depends_on: ["011.00", "014.00"]
---

# Stack Ports

## What we are trying to achieve

Port a project to another stack. openlanes generates a "Port from X to Y" plan, runs both apps side by side, and has the verifier check that they behave the same. A final plan retires the old code, and that plan always goes to the human.

## Why it matters

Some projects move from one language or framework to another. Without parity checks, nobody can show that the rewrite behaves like the original.

## What already exists

- Decision M18 in `docs/decisions/decisions-on-merge-modes-and-verification.md:172-177`.
- Plan 011 (`init-interview`) asks whether to port or start fresh, and records `stack.from` and `stack.to`. It leaves executing the port to this plan (`.plans/011.00-📋 → init-interview/spec.md:30`, `:45`).
- Plan 012 (`app-runner-and-preview`) starts an `app:` block of processes on ports from 11100. Plan 014 (`chewie-verifier`) follows `## How to test` against the running app.

## What research needs to settle

- How the port plan and its units are generated from leah's inventory of the old code.
- How the outputs of two running apps are compared.

## Research

### Method

- Read the code on `origin/main` (`b2b5176`) that a port would go through: plan creation, spec frontmatter, config, the merge boundary and the dependency gate.
- Read the specs of the plans this one consumes:
  - 011, 012, 013 and 014 on `main`;
  - 008, from PR #23 (`kig/008.00-plan-dependencies`);
  - inquirex PR inquirex/inquirex#13.
- No web search. Every question here is about this repository's own design, not about how a library behaves upstream.
- Checked the toolchains with `go version` (prints `go1.26.4 darwin/arm64`) and `python3 -c "import flask"`.

### Findings

**F1. Nothing yet ports, detects or records a stack.**

- `Config::KEYS` is `project lane frontend jobs redis_url commands` (`lib/openlanes/support/config.rb:84`), and `Config.parse` refuses any other key (`config.rb:125-129`). `stack:`, `app:` and anything describing a port cannot be stored until plans 011 and 012 add them.
- `rg -n "parity|legacy" lib` finds only `Mailbox#legacy_path` (`lib/openlanes/plans/mailbox.rb:66`), which is unrelated. No code compares two apps.

**F2. Plans can already be created from code, and a generator can reuse that.**

- `Lifecycle.create(dir:, **)` (`lib/openlanes/lifecycle.rb:13`) calls `Creator#create(words:, after:, status:, prs:)` (`lib/openlanes/lifecycle/creator.rb:38`). That takes the next major ordinal and creates the folder in ⚪️ with a `state.json` (`creator.rb:139-148`).
- `Brief#scaffold` writes the H1 and four headings (`lib/openlanes/lifecycle/brief.rb:29-34`, `:144-147`). A generator can write a fuller `spec.md` in place of the scaffold.
- A new plan starts in the `full` lane, so `leah-researcher` takes it first (`agents/leah-researcher.md:4`, `handles: [new]`).
- `luthen-rael-planner` then splits it into work units. Each unit has Discipline, Owns, Must not touch, Depends on and Done when (`agents/luthen-rael-planner.md:24-29`). This is the route M18 names: "leah inventories the old code, luthen-rael splits it into units".
- leah's contract is a free-form `## Research` chapter (`agents/leah-researcher.md:20-40`) with no inventory shape. luthen-rael therefore has no fixed list to turn into units.

**F3. Retiring the old code after the port can already be expressed.**

- PR #23 adds `depends_on: ["NNN.MM"]` to spec frontmatter (`lib/openlanes/plans/spec.rb:23` on that branch).
- It also adds `Plans::Dependencies`, which holds a dependent plan until every plan it depends on is ✅ or deployed (`lib/openlanes/plans/dependencies.rb:14`, `DONE = %i[approved deployed]`).
- A retirement plan with `depends_on: [<port plan>]` therefore waits for the port. This plan needs no gate of its own.

**F4. No per-plan switch says "always goes to the human".**

- The engine never merges today. A plan whose review approved it is parked as "approved, awaiting merge" (`lib/openlanes/engine/dispatcher.rb:1090-1092`), and `gh pr merge` stays in `UNGRANTABLE` (`lib/openlanes/execution/executor.rb:338`).
- M2 and M4 add an engine merge under `merge.by: agent`, a project-wide key that plan 011 stores. Nothing overrides it for one plan.
- Spec frontmatter has no `merge` key (`lib/openlanes/plans/spec.rb:54-80`, `Data.define(:lane, :frontend, :depth, ...)`).
- So in an agent-merge project, the engine would merge a retirement plan unless something stops it.

**F5. Plan 012 runs one app per project.**

- Plan 012 defines a single `app:` with `kind` and `processes[]`, at most one of them `preview: true` (`.plans/012.00-📋 → app-runner-and-preview/spec.md:56-57`).
- Ports come from one machine-wide registry starting at 11100 and are exported as `PORT_<NAME>` (`:58-59`).
- Two apps side by side need either a second process list or process names that do not collide in the single list.

**F6. Parity needs observations the verifier can compare, and plan 014 has not defined them yet.**

- M1 has chewie follow `## How to test` "step by step, through a headless browser for web apps or a shell otherwise, and compare what it sees with what the steps promise" (`decisions-on-merge-modes-and-verification.md:15`).
- M18 asks for something stricter: "each unit's test steps run against both, and their outputs must match" (`:176`).
- Plan 014's spec on `main` is still only a brief (`.plans/014.00-⚪️ → chewie-verifier/spec.md`). Its full spec is being written on `kig/014.00-spec-chewie-verifier`, which has not been pushed. No step format or observation type exists to build on yet.
- Two outputs can only match once differences that do not matter are removed: header order, JSON key order, whitespace in rendered HTML, generated ids and timestamps. A byte comparison would reject a correct port. This is a judgement, not measured against a real port.

**F7. Counting coverage on the new stack only follows from M15.**

- `.openlanes.coverage.yml` has one `command` and one `report` (M15, `decisions-on-merge-modes-and-verification.md:139-145`). Plan 013 runs the command in a clean checkout and parses the report (`.plans/013.00-📋 → coverage-gate/spec.md:52-60`).
- If that command runs only the new stack's tests, the old code never enters the figure. Plan 013 needs no change; luke has to be told to write it that way.

**F8. The interview belongs to plan 011, and inquirex PR #13 provides its non-interactive path.**

- Plan 011 owns the port-or-start-fresh question and the `stack.from` and `stack.to` keys.
- inquirex PR #13 (open, version 0.12.0) adds:
  - `Engine#back`, `#can_back?` and `#previous_answer`;
  - `Inquirex::Headless.new(definition, answers:, yes:).call`, which returns `{path_taken:, answers:, steps_completed:}` and raises `Headless::MissingAnswer` for a required step with no answer.
- Any question this plan adds to plan 011's flow must have a default, so `init -y` passes through `Headless` without raising.

**F9. The acceptance fixture needs its own Python environment.**

- `python3 -c "import flask"` fails on this machine with `ImportError: cannot import name 'Markup' from 'jinja2'`: the user-site Flask is older than its Jinja2.
- A Flask fixture must bring its own `uv` environment with pinned versions. Go 1.26.4 is installed.

### Contradictions

| Source | Says | Code | What runs today |
| --- | --- | --- | --- |
| M18 (`decisions-on-merge-modes-and-verification.md:177`) | Retirement "always goes to the human before merging" | M4's `merge.by` is project-wide, and spec frontmatter has no per-plan merge key (`spec.rb:54`) | Nothing merges yet (`dispatcher.rb:1092`). Once plan 014's merge lands, an agent-mode project would merge the retirement plan. |
| M12 and plan 012 | One `app:` per project | M18 needs two apps running at once | Neither: `app:` is unbuilt (`config.rb:84`) |
| M1 | chewie compares the app with "what the steps promise" | M18 compares the old app with the new one | Neither: chewie does not exist (`ls agents/`) |
| This folder's draft `spec.md` | Brief headings appeared twice, the second set empty | `Brief#scaffold` writes the four headings once (`brief.rb:144-147`) | A second scaffold write over an edited brief, also seen in plans 014 and 015. Removed here, not investigated further. |
| Draft frontmatter | `depends_on: ["011", "014"]` | PR #23 documents `["NNN.MM"]` (`spec.rb:23` on that branch) | Rewritten as `["011.00", "014.00"]` |

### Could not settle

1. Is a port one plan whose units come from the inventory, or one plan per inventory row? M18's wording allows either.
1. The step format plan 014 will use for `## How to test`, and the observation type chewie records per step. Plan 014's spec is not on `main`.
1. Where the old app's processes are declared, and who writes them. The old app exists before any build, and leah may only write `spec.md` (`agents/leah-researcher.md:15`).
1. The name of the per-plan "a human merges this" override, and whether anything besides the generator may set it.
1. How stateful apps are compared: two stores seeded the same way, or one store both apps share.
1. Whether each PR re-runs earlier units' parity steps as a regression sweep, or only its own.
1. What triggers plan generation: `init` only, or also a command for a project that is already initialised.

### Findings, Conclusion & References

Everything M18 needs is unbuilt, with two exceptions: plans can already be created from code (F2), and the dependency gate will exist once PR #23 merges (F3). The work divides into:

- a generator that creates two linked plans;
- a fixed inventory shape that leah writes and luthen-rael reads;
- a second app declaration;
- a parity mode in chewie that compares normalised observations;
- a per-plan human-merge override.

The interfaces still open belong to plans 011, 012 and 014. They are named in Open questions.

References (local, retrieved 2026-10-14):

- `lib/openlanes/support/config.rb`, `lib/openlanes/lifecycle.rb`, `lib/openlanes/lifecycle/creator.rb`, `lib/openlanes/lifecycle/brief.rb`, `lib/openlanes/plans/spec.rb`, `lib/openlanes/plans/status.rb`, `lib/openlanes/plans/mailbox.rb`, `lib/openlanes/engine/dispatcher.rb`, `lib/openlanes/execution/executor.rb`
- `agents/leah-researcher.md`, `agents/luthen-rael-planner.md`, `agents/yoda-writer.md`
- `docs/decisions/decisions-on-merge-modes-and-verification.md` (M1, M2, M4, M10–M18)
- `.plans/011.00-📋 → init-interview/spec.md`, `.plans/012.00-📋 → app-runner-and-preview/spec.md`, `.plans/013.00-📋 → coverage-gate/spec.md`, `.plans/014.00-⚪️ → chewie-verifier/spec.md`
- PR #23 `kig/008.00-plan-dependencies`: `lib/openlanes/plans/dependencies.rb`, `lib/openlanes/plans/spec.rb`
- inquirex/inquirex#13, "Add Engine#back and a headless driver; 0.12.0" (open)

No paywalled or licensed sources were used.

## Framings considered

1. **One port plan plus one retirement plan.**
   - The generator creates two folders.
   - leah's inventory of the old code becomes luthen-rael's work units inside the port plan, and each unit's `## How to test` steps are its parity probes.
   - The retirement plan has `depends_on` pointing at the port plan, and is marked for a human to merge.
1. **One plan per inventory row.** leah's inventory creates N plans, each with its own PR, and a retirement plan that depends on all of them.

**Chosen: 1.**

- M18 names one generated plan that luthen-rael splits into units, and luthen-rael already plans units inside one folder (`agents/luthen-rael-planner.md:24-30`).
- Framing 2 needs a new agent that creates plans from research, which no contract allows today (`agents/leah-researcher.md:15`, `writes: [spec.md, blocked.md]`).
- Open question 1 keeps framing 2 available.

## Goal

A project moving from one stack to another (Flask to Go, Rails to Hanami) can be ported by the factory with evidence that the new app behaves like the old one.

- openlanes generates a "Port from X to Y" plan and a "Retire X" plan.
- The port plan's units come from a fixed inventory of the old code's observable behaviour.
- Both apps run side by side.
- A unit's PR merges only when its test steps produce the same normalised output from the old app and the new one.
- Retiring the old code waits for the port, and never merges without a human, whatever `merge.by` says.

## Non-Goals

- Automatic code translation or transpiling. luke and rey still write the new stack by hand from the inventory.
- Parity of performance, memory or latency. Only observable output is compared.
- Pixel-level screenshot comparison. Templates differ legitimately between stacks, so visible text is compared instead (open question 4).
- Data migration between the two apps' production stores. Both apps run against fixtures.
- Partial ports, such as splitting out only the API and leaving the UI behind. The whole app is ported.
- The interview itself, its keys and `docs/decisions/stack.md`. Plan 011 owns them; this plan only reads `stack.from` and `stack.to`.
- The verifier, its labels, its screenshots and the engine merge. Plan 014 owns them; this plan adds a parity mode to them.

## In scope

Each item has its check.

1. **Port plan generator.** `Lifecycle.port(dir:, from:, to:)` creates two folders through `Creator#create`, `NNN.00-⚪️ → port-from-<from>-to-<to>` and `NNN+1.00-⚪️ → retire-<from>`, each with a generated `spec.md`.
   - Check: a spec on a `PlansFixture` tree asserts both folder names, their ordinals, and each `spec.md`'s frontmatter and headings.
1. **Port spec content.** The port plan's `spec.md` carries:
   - frontmatter `port: { from: <from>, to: <to> }` and `starts: research`;
   - an `implementation_requirements:` entry saying `.openlanes.coverage.yml` measures the `<to>` code only (M18, F7);
   - a `## What research needs to settle` that asks leah for the inventory (item 3);
   - a `## How to tell it's working?` that says every inventory row passes parity.

   Check: the generator spec reads it back through `Plans::Spec.for` and finds no `problems`.
1. **Fixed inventory shape.** `agents/leah-researcher.md` gains a rule for plans whose frontmatter has `port:`. Their Research chapter holds `### Inventory`, a table of every externally observable behaviour of the old app, with these columns:
   - `id` (`I1`…);
   - `kind` (`http`, `cli`, `page`, `job`);
   - `entry`, such as `GET /todos` or `bin/app list`;
   - `old code` (`file:line`);
   - `probe`, a step that exercises the entry.

   Check: an eval case `evals/cases/leah-researcher/port-inventory.yml` on a fixture Flask app asserts the table exists and has a row for every route in the fixture.
1. **Inventory to units.** `agents/luthen-rael-planner.md` gains a rule for port plans. Every inventory row is covered by exactly one unit, and that unit's `Done when` includes the row's probe as a parity step.
   - Check: an eval case under `evals/cases/luthen-rael-planner/` asserts each `I<n>` is named exactly once.
1. **Old app declared beside the new one.**
   - `Config` accepts `app.legacy`, with the same `processes[]` schema as `app.processes` (plan 012).
   - Process names in `app.legacy` get a `legacy_` prefix, so `PORT_LEGACY_<NAME>` never collides with the new app's ports.
   - Check: a config spec loads both lists, and rejects `app.legacy` when no `port:` plan exists, naming the file. A supervisor spec starts both lists and receives disjoint ports from the registry.
1. **Who writes `app.legacy`.** luke's first unit in a port plan writes `app.legacy`. hansolo rejects that first build if `app.legacy` is missing.
   - Check: an eval case under `evals/cases/hansolo-reviewer/` rejects a port-plan diff without `app.legacy`.
1. **Parity mode in chewie.** For a plan whose frontmatter has `port:`:
   - chewie runs each `## How to test` step twice, once against `app.legacy` and once against `app.processes`;
   - each run records one `Observation` (its shape is open question 2);
   - the two are compared after normalisation (item 8), and any difference fails the step;
   - the `review-rejected` comment shows the step, both normalised outputs and a unified diff.

   Check: a verifier spec with two fixture HTTP servers that differ in one field fails with that field in the diff. With identical servers it passes.
1. **Normalisation.** Before comparing, chewie normalises each observation:
   - HTTP: status code, `Content-Type` media type, and body. A JSON body is canonicalised: keys sorted, whitespace dropped. An HTML body is reduced to its visible text with whitespace collapsed.
   - CLI: exit code, and stdout with trailing whitespace stripped.
   - Per-plan ignores go in `parity.ignore` in the port spec frontmatter: JSON pointers, plus regular expressions for text.
   - Check: one spec per rule, including key order, `\r\n` against `\n`, and an ignored `/id`.
1. **The old app cannot start.** Verification fails with "the legacy app does not start" and the last 20 lines of its log, the same as M1's rule for the new app.
   - Check: a verifier spec with a legacy process that exits 1.
1. **Retirement plan.** Its spec has:
   - `depends_on: ["<port plan>"]`, so it waits until the port is ✅ (F3);
   - `merge: human`;
   - a `## How to tell it's working?` that requires one last full parity sweep over every inventory row, before `app.legacy` and the old code are deleted.

   Check: the generator spec, plus a `Plans::Dependencies` spec showing the retirement plan held while the port plan is 🟡.
1. **Per-plan human merge.** `Plans::Spec` accepts `merge: human`. When `.openlanes.yml` has `merge.by: agent`, the engine's merge step (plan 014) skips any plan whose spec says `merge: human`. That plan waits under Needs you as it would in M4's human mode ("waiting on you: PR #N").
   - Check: an engine spec with a `GitHub` double asserts no merge call for that plan, and a merge call for a sibling plan without the key.
1. **Triggered from `init`.**
   - When plan 011's flow records a port, `init` calls `Lifecycle.port` once, after `.openlanes.yml` is written.
   - Under `-y` (inquirex `Headless`, PR #13), it generates the plans only when the flags name both `from` and `to`.
   - Running `init --reconfigure` again with the same `from` and `to` creates nothing new.
   - Check: an `init` spec with the flow driven by `Headless` answers, and a second run asserting the number of `.plans` folders is unchanged.
1. **Preview labels.** For a port plan, the two Preview tabs (one per running app, plan 012) are labelled `old · <from>` and `new · <to>`.
   - Check: a Vitest component test, and plan 012's Cypress spec in `web/cypress` extended with a two-app fixture.
1. **Acceptance fixture.** `spec/fixtures/ports/flask-todo/` holds a Flask app of about four routes, with `uv`-pinned dependencies (F9), and a reference Go port.
   - Check: a spec tagged `:port_e2e`, skipped unless `go` and `uv` are on `PATH`, starts both apps through the supervisor and runs parity on every inventory row.
   - It passes on the reference port, and fails with a diff when one Go handler is altered.
1. `bundle exec rspec` is green with no network access, and `rubocop` reports zero offenses.

## Out of scope

- **The interview question and the `stack:` keys.** Plan 011 owns them. This plan calls `Lifecycle.port` at the end of plan 011's flow.
- **Driving the app, labels, screenshots and the engine merge.** Plan 014 owns them. This plan adds a parity mode on top of plan 014's step runner.
- **Starting processes and allocating ports.** Plan 012 owns them. This plan adds a second process list to plan 012's schema.
- **Ports where both apps share one database.** Comparing writes needs separate stores seeded the same way (open question 5). A shared store needs a different design.
- **Live LLM evals in CI.** The leah, luthen-rael and hansolo cases run offline against recordings, like the other cases under `evals/cases/`. Live runs stay manual.
- **Rolling back or abandoning a port midway.** A human can discard the two plans with existing commands.

## Back end / front end

| Item | Half |
| --- | --- |
| 1, 2 Generator and port spec | `luke-backend` |
| 3, 4, 6 Agent contract rules and eval cases (leah, luthen-rael, hansolo) | `luke-backend` |
| 5 `app.legacy` config and supervisor | `luke-backend` |
| 7, 8, 9 Parity mode, normalisation, legacy start failure | `luke-backend` |
| 10, 11 Retirement plan, per-plan `merge: human` | `luke-backend` |
| 12 `init` hook | `luke-backend` |
| 13 Preview tab labels | `rey-frontend`, against plan 012's SSE payload with a `role: legacy\|current` field added |
| 14, 15 Acceptance fixture, suite | `luke-backend` |

luke fixes the `role` field in plan 012's event payload first, and rey builds against it.

## Open questions

Each has a recommendation. None is decided.

1. **One port plan or one plan per inventory row?**
   - Recommended: one port plan with units, plus a retirement plan (see Framings).
   - Revisit if a port grows too large for luthen-rael to plan as one.
1. **Plan 014's step and observation interface.** This plan assumes plan 014 exposes:
   - a step runner, `Verification::Runner#run(step, app:) -> Observation`;
   - an `Observation` value with `kind`, `status`, `content_type`, `body`, `exit_code` and `stdout`;
   - a rejection path through `openlanes review` that takes a comment body and screenshots.

   These names are not on `main`; plan 014's spec is being written on `kig/014.00-spec-chewie-verifier`. Recommended: plan 014 adopts `Observation` as a `Data.define`, so parity can compare two of them. If plan 014 lands different names, update this spec before planning.
1. **Where is the old app declared?**
   - Recommended: `app.legacy.processes` in `.openlanes.yml`, written by luke's first port unit.
   - Alternatives: a top-level `port.legacy` key, or leah writing it during research. leah's `writes:` forbids that today.
1. **Visible text or screenshots for `page` steps?** Recommended: visible text only in v1. Pixel diffs flag every change in template whitespace.
1. **Stateful apps.** Recommended: each app gets its own store, seeded from the same fixture before each step. A shared store is out of scope.
1. **Regression sweep.**
   - Recommended: each unit's PR runs only its own rows, and the retirement plan runs every row.
   - Alternative: every PR runs every merged row. Safer, but each PR gets slower as the inventory grows.
1. **Name and authority of the human-merge override.** Recommended: `merge: human` in spec frontmatter, set by the generator. hansolo rejects any diff that removes it from a retirement plan.
1. **Trigger.** Recommended: `init` only in v1. If the owner wants a standalone `openlanes port --from X --to Y` later, it can reuse `Lifecycle.port` unchanged.
1. **What `from` and `to` look like.** Plan 011 stores them as free text (its open question 9). Recommended: slugify them for folder names (`port-from-flask-to-go`) and keep the raw text in the spec frontmatter.
1. **A confirming question in `init`?** Recommended: no extra question. Choosing "port" in plan 011's flow is the confirmation, so `Headless` needs no new answer.
1. **Dependency on plans 012 and 013.** The declared `depends_on` is 011 and 014. Plan 014 depends on 012 and 013, so both are reached transitively. Recommended: keep the list as declared.

## Risks to planning or execution

- **Plan 014's interface may differ from what this plan assumes.** Items 7–9 build on names plan 014 has not published (open question 2). Planning must wait for plan 014's spec on `main`, and the planner should re-read it then.
- **Plan 011's flow is blocked upstream.** It depends on inquirex PR #13 and the gem pin (plan 011, open question 1). Item 12 is the only part of this plan that waits on it. The generator and everything after it can be built and tested by calling `Lifecycle.port` directly.
- **Normalisation is never finished.** Each new pair of stacks brings a new difference that does not matter. `parity.ignore` absorbs these, but if ignores pile up, parity stops checking anything. hansolo should flag a PR that adds more than a few.
- **Toolchains.** The acceptance spec needs `go` and `uv`. CI must either install them or skip the tag deliberately (F9).
- **The inventory can miss behaviour.** Parity covers only what leah listed. A route nobody listed is ported or dropped without a check, and the retirement sweep cannot catch the omission either.

## Conclusion

When this ships, choosing "port" during `init` creates two linked plans.

- The port plan's research is a fixed inventory of the old app's behaviour, and luthen-rael turns each row into a unit.
- chewie passes a unit only when the old and new apps give the same normalised output for its steps.
- Coverage counts the new code only.
- The retirement plan waits for the port, runs the full parity sweep once more, and always stops for a human to merge.

## How to tell it's working?

- **Plan generation.** `Lifecycle.port(dir:, from: "flask", to: "go")` on an empty `.plans` tree creates `001.00-⚪️ → port-from-flask-to-go` and `002.00-⚪️ → retire-flask`. The second folder's `spec.md` has `depends_on: ["001.00"]` and `merge: human`.
- **End-to-end parity.** With `go` and `uv` installed, `bundle exec rspec --tag port_e2e` starts `spec/fixtures/ports/flask-todo` and its Go port side by side on ports from 11100. It runs every inventory probe against both and reports parity on every row. If one Go handler is changed to return a different field, the run fails and the diff names that field.
- **Normalisation.** A JSON body with keys in a different order passes parity, and so does an HTML page with different whitespace. A different status code fails, and so does a missing field.
- **Human merge.** In a project with `merge.by: agent`, a retirement-plan PR with `ok-to-merge` and green CI is not merged; it shows under Needs you as "waiting on you: PR #N". A sibling plan without `merge: human` is merged.
- **Coverage.** The port plan's `.openlanes.coverage.yml` runs the Go tests only, so the coverage figure excludes the Flask code entirely.
- **Idempotence.** A second `init --reconfigure` with the same `from` and `to` leaves `ls .plans | wc -l` unchanged.
