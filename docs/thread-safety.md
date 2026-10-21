# Thread safety: shared mutable state

Every object under `lib/openlanes` that more than one thread can touch, who owns it, which threads touch it, and what keeps it safe. Plan 038.00 wrote it; `spec/openlanes/thread_safety_inventory_spec.rb` keeps it honest:

- a file under `lib/openlanes` that creates a `Mutex`, `Monitor`, `Queue` or `Concurrent::` object and is not named here fails the suite;
- a row whose status is `unguarded` fails the suite. A finding is fixed, not listed.

The default is a frozen value: `Data.define`, or a frozen constant. A `Mutex` or a `Concurrent::` object appears only where the threads below really share the object.

## Threads

| Thread | Started by | Touches |
| :-- | :-- | :-- |
| main (tick) | `Engine::Dispatcher#call` | the board, `@running`, `@history`, the state file, the bus |
| agent job | `Dispatcher` (`job.thread`, one per running agent) | its own `Child`, the executor's per-run state, `AgentLocks`, `PlanLocks` |
| kill | `Dispatcher` (`job.handle.kill!` on quit, discard, fence) | one `Child` |
| unblock / conversion | `Dispatcher`, `Engine::Conversions` | one plan folder, the choice converter |
| PR watch | `Dispatcher#watch` (`@watching`) | `PrWatch`, the finished map |
| timeout timer | `Execution::Clock` | one `Child` handle, through `Child#terminate` |
| control poller | `Execution::Control` | the control files list |
| spinner ticker | `UI` (`@ticker`) | `UI`'s parts, STDERR |
| verification driver | `Engine::Verification::Driver` | its own browser children |
| web request | Puma, one per request | `Web::Stores` (per thread), `Web::Demo`, `Live::Chat`, the bus |
| web background | `Web::Context::THREAD`, `Web::Demo`, `Live::Chat` | the demo board, the chat inbox |
| copilot watchdog | `Live::Copilot::Operator` | one copilot child |
| choice judge | `Live::ChoiceJudge` | its answers cache |
| app supervisor reader / waiter | `Apps::Supervisor` | statuses and log tails |
| signal trap | `cli/web`, `cli/app start` | `server.stop`, `runner.stop` |

## Inventory

| File | Object | Owner | Threads | Guard, or why none is needed | Status |
| :-- | :-- | :-- | :-- | :-- | :-- |
| `lib/openlanes/apps/runner.rb` | `@stopping` | `Apps::Runner` | runner loop, signal trap | `Concurrent::AtomicBoolean` | guarded |
| `lib/openlanes/apps/supervisor.rb` | `@statuses`, `@tails` | `Apps::Supervisor` | reader, waiter, caller | `@mutex` on every read and write | guarded |
| `lib/openlanes/engine/agent_locks.rb` | the held-locks snapshot | `Engine::AgentLocks` | tick, agent jobs | `@mutex` | guarded |
| `lib/openlanes/engine/dispatcher.rb` | `@running`, `@history`, `@finished`, `@waiting_on` | `Engine::Dispatcher` | tick, agent jobs, PR watch, unblock | `@mutex` around every cross-thread read and write | guarded |
| `lib/openlanes/engine/dispatcher.rb` | the tick itself | `Engine::Dispatcher` | any caller of `#tick` | `@tick_lock` (`Monitor`): two overlapping ticks each started the same plan; `dispatcher_stress_spec.rb` found it (fixed in 038.00) | guarded |
| `lib/openlanes/engine/dispatcher.rb` | `@clock` | `Engine::Dispatcher` | tick, agent jobs | `Clock::System` is stateless; `Clock::Fake` holds its own mutex | guarded |
| `lib/openlanes/engine/narrator.rb` | the narration buffer | `Engine::Narrator` | tick, agent jobs | `@lock` | guarded |
| `lib/openlanes/engine/plan_locks.rb` | the held plan set | `Engine::PlanLocks` | tick, agent jobs | `@mutex` | guarded |
| `lib/openlanes/engine/rebase.rb` | `@tallies` | `Engine::Rebase` | agent jobs | `@mutex` | guarded |
| `lib/openlanes/engine/state_file.rb` | `@data` (the restart file) | `Engine::StateFile` | tick, agent jobs | `@mutex` around every write and the heartbeat | guarded |
| `lib/openlanes/execution/boundary.rb` | `@sanctioned` pushes | `Execution::Boundary` | agent jobs, publisher | `@lock` | guarded |
| `lib/openlanes/execution/child.rb` | `Child.@live`, the list of spawned groups | `Execution::Child` | agent jobs, `at_exit` | class-level `@mutex` | guarded |
| `lib/openlanes/execution/child.rb` | one child's `@status`, `@terminating`, pipe | the `Child` | agent job (reader), timeout timer, kill thread | `@guard` per child | guarded |
| `lib/openlanes/execution/clock.rb` | the timer thread and deadline | `Execution::Clock` | agent job, timer | `@mutex` | guarded |
| `lib/openlanes/execution/control.rb` | `@files`, the control files to sweep | `Execution::Control` | agent jobs, poller | `@mutex` | guarded |
| `lib/openlanes/execution/executor.rb` | `@compaction`, per-run handle state | the run handle | agent job, tick (`compact`, `kill!`) | `@mutex` | guarded |
| `lib/openlanes/adapters/capabilities.rb` | each adapter's `CAPABILITIES` | the adapter class | any | frozen `Data` | frozen |
| `lib/openlanes/live/event_bus/base.rb` | a bus | its caller | any | frozen; all state lives in the store behind it | frozen |
| `lib/openlanes/live/chat.rb` | `@pages`, `@unavailable`, the subscriber | `Live::Chat` | web requests, chat thread | `@lock` (`Monitor`, re-entrant) | guarded |
| `lib/openlanes/live/choice_converter.rb` | the conversion cache | `Live::ChoiceConverter` | unblock, conversions | `@mutex` | guarded |
| `lib/openlanes/live/choice_judge.rb` | `@answers` | `Live::ChoiceJudge` | caller, judge thread | `@mutex` | guarded |
| `lib/openlanes/live/claims.rb` | `@held` | `Live::Claims` | tick, publisher | `@mutex`; the claim itself is `SET NX` in the store | guarded |
| `lib/openlanes/live/copilot/operator.rb` | the running child, the turn | `Live::Copilot::Operator` | web request, watchdog | `@mutex` for the child, `@turns` serialises turns | guarded |
| `lib/openlanes/live/interviewer.rb` | the interview state | `Live::Interviewer` | web requests | `@mutex` | guarded |
| `lib/openlanes/live/memory_store.rb` | `@data`, `@expiry`, `@groups`, `@subscribers` | `Live::MemoryStore` | every thread with the store | `@mutex` (`Monitor`, so `multi` can call its own writes) | guarded |
| `lib/openlanes/live/memory_subscriber.rb` | `@queue` | one subscription | publisher, reader | `Thread::Queue` | guarded |
| `lib/openlanes/live/publisher.rb` | `@log` | `Live::Publisher` | tick, agent jobs | `@log_mutex` | guarded |
| `lib/openlanes/live/run_state.rb` | concurrency, run fields | `Live::RunState` | tick, web commands | `@mutex` | guarded |
| `lib/openlanes/support/clock.rb` | `Clock::Fake` time | the spec | stress threads | `@mutex` | guarded |
| `lib/openlanes/support/spawner.rb` | `Spawner::Fake` calls and pids | the spec | stress threads | `@mutex` | guarded |
| `lib/openlanes/support/ui.rb` | `@parts` of a line | `UI::Line` | ticker, worker | `@lock` | guarded |
| `lib/openlanes/support/ui.rb` | `results` of `UI.each` | the call | workers | `Concurrent::Hash` | guarded |
| `lib/openlanes/support/ui.rb` | `@print_mutex` | `UI` | workers | created once at load; it was a lazy `\|\|=` that two threads could each win (fixed in 038.00) | guarded |
| `lib/openlanes/web/context.rb` | `stopping` | `Web::Context` | web requests, signal trap | `Concurrent::AtomicBoolean` | guarded |
| `lib/openlanes/web/demo.rb` | `@board` | `Web::Demo` | web requests, demo thread | `@mutex` | guarded |
| `lib/openlanes/web/stores.rb` | `@by_thread` | `Web::Stores` | web requests | `@mutex`; each thread then has its own store | thread-local |
