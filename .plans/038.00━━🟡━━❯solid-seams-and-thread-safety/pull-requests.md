# Pull Requests

## Back end, rounds 1 and 2 (luke-backend)

Every unit under `## Backend` is built. There is no front end, so no contract and no mailbox (plan.md, `## Frontend`).

| Unit | What landed | Proof |
| :-- | :-- | :-- |
| B1 | `Live::EventBus` (`for`, `Base`, `RedisBus`, `MemoryBus`, `Transaction`) | `spec/openlanes/live/event_bus_spec.rb` runs the shared contract `spec/support/shared_examples/event_bus_contract.rb` on both buses |
| B2 | `live.rb`, `news`, `publisher`, `commands`, `mail`, `copilot`, `chat` call the bus | the existing Live specs, on `MemoryBus` |
| B3 | `web/app.rb`, `web/demo.rb` call the bus | `spec/openlanes/web/event_bus_integration_spec.rb`: real Puma, real `Live::Publisher`, real HTTP `GET /api/events`; board seq, reply order, `Last-Event-ID` resume |
| B4 | `OpenLanes::Clock` (`System`, `Fake`), `OpenLanes::Spawner` (`System`, `Fake`); `Child`, `Web::Launcher`, `Vcs::Refresh` take `spawner:` | `clock_spec.rb`, `spawner_spec.rb`, `execution/child_spawner_spec.rb` |
| B5 | `Dispatcher` takes `clock:`; `sleeper:` kept, falling back to `clock.sleep`; every engine `Time.now` goes through `Clock` | `engine/dispatcher_clock_spec.rb` |
| B6 | `Adapters::Capabilities`; `Base#capabilities` abstract; claude, codex, pi declare theirs; `Adapters.lean_flags` replaces `Claude::LEAN` in `brief.rb` | `adapters/capabilities_spec.rb` |
| B7 | `docs/thread-safety.md`; fixed `UI.report_line`'s lazy `\|\|=` mutex | `thread_safety_inventory_spec.rb` |
| B8 | 8 threads tick one dispatcher together | `engine/dispatcher_stress_spec.rb`, green 20 of 20 |

The stress spec found a real race: eight overlapping `Dispatcher#tick` calls started one plan eight times. `#tick` now runs under `@tick_lock`, a `Monitor`, and the inventory has a row for it.

### Checks from the spec

All the `rg` checks print nothing:

- `rg "store\.(publish|subscriber|xadd)|tx\.xadd" lib`: only `live/event_bus/base.rb`
- `rg "Time\.now" lib/openlanes/engine`
- `rg "Process\.spawn" lib`: only `support/spawner.rb`
- `rg "Adapters::Claude" lib`: nothing outside `adapters/`
- `rg "adapter.*\.name ==|case .*adapter" lib/openlanes/{execution,engine}`

### "Runs alone under the global lock (034)"

034 is not built. Following plan.md's decision (open question 4), this plan does not wait for it, and the criterion is met by the operator running no other plan while 038 builds. A human may still overturn that.

### Suite

- `bundle exec rubocop`: 544 files inspected, no offenses detected, exit 0
- `bundle exec rspec`: 4039 examples, 0 failures, 9 pending, coverage 98.83%, exit 0 (baseline: 3984 examples, 0 failures, 9 pending)
- A first full run failed `spec/openlanes/live/unblock_spec.rb:59`: it asserted before the agent thread had recorded its call. It passes alone, and `drain` now waits through `start_agents`.
