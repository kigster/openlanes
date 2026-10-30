# Decisions on the dry-rb architecture refactor

Decided with Konstantin, starting 2026-10-24. The goal: a codebase that reads crystal clear. SOLID, small classes, components that can be swapped, and metaprogramming where it saves lines without hiding behaviour.

## A1. dry-system wires the application

- Components register themselves from `lib/` through the existing Zeitwerk loader; the container key follows the file path, so path, constant and key cannot disagree.
- Collaborators arrive through `Deps[...]` injection. Specs swap a component with the container's stubs instead of passing doubles through constructors.
- Providers own boot and shutdown of the outside world: Redis, GitHub, Linear, the event bus.
- Rejected: hand-registered dry-container plus dry-auto_inject (a second list of every component), and plain constructor injection (what #127 did, which does not scale past one namespace).

## A2. Coding agents are registered adapters

- `claude`, `codex` and `pi` become components registered under one namespace, `adapters.<name>`, and resolved by name from an agent's or a plan's `adapter:`. Today they sit in a hand-written hash in `Adapters.registry`.
- Adding an adapter means adding one file that satisfies the adapter contract; nothing else in the engine changes.

## A3. The HTTP API documents itself

- The Sinatra API is the contract between the engine and any front end, so the bundled web page can be replaced, by a native app for instance.
- The API publishes an OpenAPI document generated from the code, never written by hand.
- Deferred past 4.0 (A4). How it is generated is still open.

## A4. What 4.0 is, and in what order

- The published gem is 3.1.0. 4.0 ships the refactor, the cleanup, plan dependencies and the example apps; `version.rb` already reads 4.0.0 and stays unpublished until then.
- Order: (1) a fast Leah; (2) the dry-system foundation with logging and OpenTelemetry as providers; (3) tasks; (4) `ol start` in a blank folder; (5) the planner writes dependencies (A6); then the examples. The self-documenting API (A3) comes after 4.0.

## A5. No vendor tracing gem in openlanes

- `newrelic_rpm` and `newrelic-infinite_tracing` leave the Gemfile and `web/app.rb`. The gem instruments itself through the OpenTelemetry API only; a user who wants New Relic, Honeycomb or anything else wraps the gem and adds their exporter.

## A6. The planner writes plan dependencies

- `luthen-rael-planner` sets `depends_on:` while planning, because planning is where the implementation is first seen and dependencies show up there, not in the spec. Starting a plan's planning therefore includes deciding what it waits for.
- Rejected: yoda, who writes the spec before the implementation is known; a separate agent ahead of planning, which would decide with less than the planner knows.

## Open, raised 2026-10-24 for version 4.0

Recorded as said, not yet decided. What exists today is noted beside each.

- **Visibility.** A readable log of what the engine is doing, plus OpenTelemetry instrumentation a user enables by adding a config file and an exporter gem (Honeycomb, New Relic). Today: SemanticLogger, and `web/app.rb` hard-requires `newrelic_rpm`.
- **Tasks.** A task is part of a plan and maps to one pull request when a plan is too big for one. Two builders can work on two tasks of one plan in parallel once they have agreed the interfaces, then test the integration. Today: the planner writes work units into `plan.md`, but one builder builds the whole plan into one pull request.
- **`ol start` in a blank folder.** An agent grills the user up front, writes `APPLICATION.md`, then `BACKLOG.md` (overlaps plan 048.00).
- **Plan dependencies.** Settled in A6.
- **Leah is too slow.** She fans out sub-agent waves, runs the test suite and settles questions herself, with a 20-minute timeout. Wanted: a quick scan for what in the codebase can be reused, a web search for an existing component, and no decisions.

## A7. Leah scans and searches; she decides nothing

- Input: the topic in `spec.md` and its `## What research needs to settle` list.
- She scans the repository (`rg`, reading files) for what can be reused, by path, and runs a few web searches for an existing gem, crate or package, each with its URL and a one-line fit.
- She writes `## Research` with three parts: **Reuse in this repo**, **Existing components**, **Open questions for yoda**.
- She does not dispatch sub-agents, run the test suite, or answer the open questions; yoda or the human settles them.
- Timeout drops from 1200 to 300 seconds; the model stays `haiku`.

## A8. Small classes, and metaprogramming that declares

- Enforced by rubocop with no todo exemptions once the refactor is done: a class at most 100 lines, a method at most 10, at most 4 parameters, AbcSize at most 20. Today the limits sit in `.rubocop.yml` but 58 classes and 3 methods exceed them unenforced. Each refactor pull request removes exemptions and never adds one.
- Allowed, because it declares: `Data.define`; class-level DSLs (`Status`, `aasm`, `Deps[...]`, dry-cli `option`); `def_delegators`; `define_method` over a constant list in the same file; `self.inherited` and `self.included` hooks that give each subclass or includer its own class instance variables (a per-class registry, defaults, a declared list), including `instance_variable_set` and `instance_variable_get` on that class inside the hook's own module.
- Not allowed, because it hides: `method_missing`; `send` or `public_send` with a computed name; reaching into another object's instance variables; monkey-patching core classes; `define_method` from names built at runtime.
- Test: `rg "def <name>"`, or a literal name in the file that declares it, finds every method that exists.

## A9. Behaviour is frozen while the structure moves

- A restructuring pull request changes no behaviour: CLI flags and output, files written under `.plans/`, and API responses stay as they are, and the existing specs pass with their assertions untouched. Specs may move with their class and gain examples for new classes.
- New behaviour (A5, A6, A7, tasks, spans) lands in its own pull requests, never inside a restructuring one.

## A10. Class diagrams are generated, before and after

- Generated from the code by `openlanes uml`, which prints Mermaid on STDOUT, and written to `docs/architecture/`, never drawn by hand.
- Classes only, no methods or attributes. Edges are directed and typed: inherits, includes, and uses (a class references or is injected with another). `Data.define` value types are folded into the class that owns them.
- Two levels: one namespace map (namespaces and the directed dependencies between them, which is where coupling shows), and one class diagram per namespace.
- `docs/architecture/before/` is generated once now and frozen. `docs/architecture/` is regenerated by every refactor pull request, and a spec fails when it is stale, as `docs/WORKFLOW.md` already works.

## A11. One agent, one seam per pull request

- A single delegated agent in its own worktree works the order in A4: Leah (A7) and New Relic (A5); `openlanes uml` and the frozen `before/` snapshot (A10); dry-system with its providers (logger, OpenTelemetry, GitHub, Linear, Redis); then Dispatcher, Executor (registering adapters, A2), PlanState, RunWorkflow, and the rest by size.
- Every pull request: `just ci` green, its classes off the rubocop exemptions, diagrams regenerated.
- Reviewed by Claude in the orchestrating thread, plus an independent reviewer on another model family (Codex) for the large seams. Only Konstantin merges. Work in flight rebases after each merge.

## A12. `ol uml` draws the project being built; `ol uml self` draws OpenLanes

- `ol uml` parses the project's Ruby source statically with Prism (`lib/`, and `app/` in a Rails project) and never loads or boots it. Agents can read the map too: the planner before splitting tasks, the reviewer comparing a pull request's before and after.
- `ol uml self` draws the gem's own `lib/`. Neither draws `spec/`.
- `ol uml` prints the namespace map, `ol uml <namespace>` one namespace's class diagram, and `-o FILE` writes it to a file.

## A13. Logs and traces come from one set of instrumentation events

- The engine publishes instrumentation events through dry-monitor; a SemanticLogger subscriber writes the log and an OpenTelemetry subscriber writes spans, so a log line and its span cannot disagree.
- Log: `log/openlanes.log` in the project, one line per state transition, agent start and finish (plan, agent, adapter, model, duration, cost, exit status), push or pull request opened, conflict, and question raised. Standard `-l`, `-L` and `--log-format json` flags.
- Traces: openlanes depends on `opentelemetry-api` only, a no-op until an SDK is present. Spans: `run` → `round` → `plan.step` (one agent invocation) → `adapter.call`, with ordinal, agent, from and to state, tokens and cost.
- A user enables tracing by adding `opentelemetry-sdk` and `opentelemetry-exporter-otlp` and setting the standard `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS`. Honeycomb and New Relic both take OTLP, so neither needs a vendor gem. An optional `telemetry:` section in `.openlanes.yml` sets `service_name` and lists extra gems to require for those who wrap openlanes.

## A14. `ol new <appname>` is the front door

- `new` stops being an alias of `create`; a changelog line covers scripts that used it.
- `ol new my-app`: creates `./my-app` (refusing a non-empty one), `git init`, runs the `ol init` interview, then the application grilling agent, which asks one question at a time and writes `.plans/APPLICATION.md` and then `.plans/BACKLOG.md`; offers to mint the first plans from the backlog; prints `cd my-app && ol start`.
- `--application FILE` starts from an existing `APPLICATION.md`: it is copied in, and the grilling goes straight to `BACKLOG.md`, asking only about what the file leaves open.
- `--example <name>` copies a template instead and skips the grilling (E1). `--github` asks, then runs `gh repo create`. `-y` takes every default and skips the grilling.
- `ol start` in a folder with no `.openlanes.yml` offers the same steps in place, so there is one implementation of a blank start, not two. `ol init` stays the command for an existing codebase.

## A15. `ol setup` comes first and owns tools and authentication

- `ol setup` installs the tools and authenticates `gh`; it runs before `ol new` or `ol init`. Neither of those checks `gh` auth again. When a required tool is missing they say to run `ol setup` and stop, rather than repeating its work.

## A16. `ol init`, done properly

- The interview adds: (a) the adapter and model per phase; (b) no `origin` remote turns pushing off; (e) a `telemetry:` section (A13); (f) `app:` processes, asked only when the detected stack has a runnable app; (g) coverage: the command, the report and its format, and the minimum, detected from the stack where it can be (SimpleCov, `cargo llvm-cov`, Vitest) and defaulting to 95.
- (c) `.openlanes.yml` is written with a comment above every key, so the file documents the keys nobody was asked about.
- (d) `ol init --check` validates an existing file and explains each problem.
- Coverage lives only in the `coverage:` section of `.openlanes.yml`. The reader already ignores `.openlanes.coverage.yml` and only warns that it exists; the stale copy still tracked in this repository is deleted, and the warning goes once 4.0 ships.

## What earlier plans already settled

Found by scanning `.plans/` and `docs/decisions/` on 2026-10-24. These stand unless a decision above overrides them.

- **This refactor is plan `045.00` solid-sweep** (S19 in `decisions-on-distributed-engine-and-solid-refactor.md`): one responsibility per class, collaborators injected through the `038` ports, facade-only access between namespaces, a functional core over frozen `Data`. A1 to A16 replace its "about 80% SOLID" with the stricter A8 limits and wire it with dry-system.
- **Concurrency (S15):** the bare `Thread.new` call sites move to concurrent-ruby (`Concurrent::Map`, `TimerTask`, a bounded `ThreadPoolExecutor`), and fallible operations return dry-monads `Result`. No Ractors, no fibers.
- **A `Judgment` port (S19)** for narrow typed decisions; Jev only when `TYPESAFE_API_KEY` is set, otherwise the default adapter's cheapest model.
- **The `038` seams exist** (`EventBus`, `Clock`, `Process`, the adapter capability contract) and become dry-system components rather than being rebuilt.
- **The global lock (`034.00`, R6):** a refactor touching more than half the codebase runs alone; nothing else starts until it merges. That is A9 and A11 enforced by the engine.
- **Dependencies are written today by `ewoki-linker`** (plans `008.00`, `008.01`), in its own state `ready_for_linking` before planning, editing only `spec.md`. A6 moves that job to the planner; see A17.
- **A grilling interviewer exists** (`029.00`): `Live::Interviewer` asks up to five questions, each with a recommended answer, when an idea is added on the page, and writes `## Decisions` into `spec.md`. The application grilling in A14 builds on it rather than starting over.
- **Pairs already build in parallel:** luke-backend and rey-frontend work one plan as a pair, through `contract.md`. Tasks generalise that pair to N builders, each on its own pull request.
- **`ol init` is mid-build in `011.00`** (🟡). A16 lands after it, not inside it.
- **Adapters (D6, D10):** a new coding agent is one `Adapters::Base` subclass plus one registry entry; `040.00` adds Gemini and Grok. A2 removes the registry entry.
- **The remote UI (`043.00`, `044.00`)** depends on the API contract that A3 defers.

## A17. The planner resolves dependencies; ewoki-linker is retired

- luthen-rael writes `depends_on:` while planning, and may write that one key in `spec.md`, so the runner reads it where it does today.
- `ewoki-linker`, the `ready_for_linking` state and the dispatcher gate that sends unlinked plans to it are removed.
- Any number of dependencies is fine: the runner orders them topologically. Only a cycle goes to a person, since no ordering can resolve it. The rule from `008.00` that more than three dependencies go to a person is dropped.

## A18. `ol init` fills one typed architecture structure

Decided with Konstantin, 2026-10-30. This overrides plan `011.00`'s "inquirex-tty is not added".

- `Setup::Architecture` holds closed lists of symbols (`ci`, `languages`, `frameworks` and so on), each list a constant. The form's options, the extraction schema and the file's validation all read those constants. A value outside a list is `:other`, with its name in `notes`.
- Two snapshots, `current` and `target`, are serialized under `architecture_decisions:` in `.openlanes.yml`, so what the repository holds now stays apart from what the person wants.
- The form is an Inquirex DSL file, `lib/openlanes/setup/project_form/dsl.rb`, and it must pass the inquirex-tty validator. Its JSON is what the inquirex-webui and inquirex-widget packages would render later.
- Most questions are multi-select, because a repository usually has several of each: both GitHub Actions and CircleCI, for instance.

## A19. Scan first, then preselect

- `ol init` scans the repository before it asks anything. What it finds is preselected, and the person can change it. Only a flag typed on the command line skips a question.
- What the description states is also preselected, in the `target` questions, rather than skipping them.
- An empty folder has no `current` section.

## A20. The person chooses how much detail to give

- The first question is low, medium or high. Each attribute names the lowest detail that asks it: 10, 15 or 21 topics.

## A21. Extraction uses the person's credentials, never ours

- Order: an API key from the environment (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `XAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`), then a local Ollama, then a signed-in CLI (`claude`, `codex`, `grok`, `gemini`, each in a read-only mode), then no extraction, with every question asked.
- Ollama is found through `OLLAMA_HOST` or its default port, with a one second timeout, and uses the first model pulled. `OPENLANES_EXTRACTION_MODEL` overrides any route's model.
- Before asking for the description, the form says where it will go.
- No OpenLanes key ships in the gem. Anything in a published gem can be read by whoever installs it, and a hosted proxy would be a service to run and defend, which this gem is not.
- A key is read from the environment only. It is never written to `.openlanes.yml`, logs or telemetry. A failure logs the error's class, because a message can quote a key or the description.

## A22. Layout and task runner come before the stack

- Without the layout nobody knows where anything goes, so the form opens with it: one application or library at the top level, like a Rails or Django app, or a monorepo. A monorepo is also asked which folders hold its projects.
- The form also asks how people and agents run tasks such as lint, test and build: `just`, `rake`, `make` and others. The maintainer prefers `just`; another person may not, so it is a question and not a default.
- Agents must read `architecture_decisions:`. An answer that only sits in a file does not tell a builder where to put things.

## A23. How the app starts and where its secrets live

- The first tier also asks how the application starts in development, how development secrets are kept, and how they reach the environment.
- When neither the description nor the scan answers, WANTED preselects `sopsy` and `direnv`, so secrets stay encrypted in git and load into the environment on `cd` into the project, plus `mprocs` and `just`. A Rails application preselects Rails credentials instead, as the global rules say.
- A recommendation is only ever preselected. `-y` records what the scan found, never a recommendation.
- The scan reads only file names for secrets, such as `.env.encrypted`, `.envrc` and `config/credentials/*.yml.enc`, and never their contents.

## Plan folders

| Plan | Decisions | Depends on |
| --- | --- | --- |
| `049.00` fast-leah-researcher | A7 | none |
| `050.00` remove-new-relic | A5 | none |
| `051.00` planner-resolves-dependencies | A6, A17 | none |
| `052.00` uml-class-diagrams | A10, A12 | none |
| `045.00` solid-sweep | A1, A2, A8 to A13 | 049, 050, 051, 052 |
| `053.00` tasks-within-a-plan | its own grilling | 045 |
| `054.00` ol-new-application-generator | A14, A15 | 045, 048 |
| `055.00` ol-init-done-properly | A16 | 011, 045 |
| `047.00` example-app-templates | E1 to E8 | 054 |
