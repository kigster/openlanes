# Notes for the reviewer: U4, the local seams

## The `.new(` check

`rg "\.new\(" lib` was narrowed to classes that have a provider key (`Vcs::GitHub`, `Linear::API`, `Live::Store`, `Live::EventBus`, `Clock::System`, `Spawner::System`, SemanticLogger). Every remaining hit outside `lib/openlanes/providers/`, each with why it stays:

| Hit | Why it stays |
| :-- | :-- |
| `vcs.rb:41` `GitHub.new(chdir: root)` | Rooted at a per-call checkout the provider cannot know; commented in place. |
| `vcs.rb:50` `GitHub.new(chdir: root)` | Same. |
| `execution.rb:20` `Vcs::GitHub.new(chdir: root)` | Same. |
| `live.rb:56` `Store.new(url:)`, `live.rb:67` | `Live.store` and `Live.connect` are the factories the `redis` provider itself calls; a factory taking a URL is not an injectable default. |
| `live.rb:59` `MemoryStore.new(**)` | The suite's in-memory store, built per example. |
| `support/log.rb:168` `SemanticLogger[...]` | `Log.logger` is what the `logger` provider hands out; it is the source, not a consumer. |

## The sweep

`rg -l "Clock::System|Spawner::System|Log\.logger|Live\.connect\(|EventBus\.for\(" lib | rg -v providers/` named 35 files at the start. Rewired to the container (the keyword and its call-time default are unchanged, so every caller that passes its own still works):

- `clock` → `Supervision::Host`, `Supervision::Crashes`, `Engine::Dispatcher` (as the object), `Engine::Extensions`, `Engine::Merging`, `Engine::Narrator`, `Engine::PrOutcomes`, `Engine::Verification::Outcome` (as `-> { Container["clock"].now }`), `Engine::QualityQuestion#ask!/#answer!`, `Engine::Runner#age!/#halted_by/#mint_run`, `Engine::CoverageGate#run`, `Engine::StateFile` (`Container["clock"].now`).
- `process` → `Supervision::Host`, `Web::Launcher`, `Execution::Child.spawn`, `Execution::AgentProcess::Starter`, `Vcs::Refresh#fetch_within`.
- `logger` → `Web::RequestLog`, when built without one.

Left as they were, by the plan's own rule (per-call objects built from arguments, and facades):

- `Live.connect(url)` in `cli/web/web.rb`, `cli/preview/subcommands/start.rb`, `setup/machine.rb`, `engine/run_workflow.rb`: each connects to a URL chosen per call (`--redis-url`, the setup's probe); `cli/mail/subcommands/send.rb` connects and **closes** its store, which the memoized `redis` key must never be.
- `EventBus.for(@store)` in `live/*.rb`, `web/demo.rb`, `web/app.rb`, `live.rb`, `engine/run_workflow.rb`: a bus over the store the object was handed, which is what the `event_bus` provider does over the container's own Redis. Taking `event_bus:` instead of `store:` would change those constructors' contracts.
- Direct `Log.logger.info(...)` calls in `supervision/supervisor.rb`, `adapters/probes.rb`, `cli/web/web.rb`, `engine/run_workflow.rb`: calls on a facade, not a default collaborator and not a construction; the `logger` provider delegates to the same facade.
- Comments and YARD that name the classes (`support/log.rb`, `uml/model.rb`, `dispatcher.rb`, `child.rb`, `request_log.rb`).

## A race the wiring exposed

dry-system starts a provider on its first resolve with no lock. Sixteen threads resolving `Container["process"]` together on a fresh container failed with `key not found: "process"` 60 times in 30 runs, and `Execution::Child.spawn` is called from one thread per job. `lib/openlanes.rb` now starts `clock`, `process` and `logger` once at boot (none reaches outside the process); the same race test then passed 20 of 20 runs. `redis`, `github` and `linear` stay lazy. `spec/openlanes/local_seams_wiring_spec.rb` asserts the three are started.
