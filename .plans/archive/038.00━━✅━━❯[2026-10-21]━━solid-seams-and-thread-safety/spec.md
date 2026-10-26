---
created: 2026-10-20
starts: research
---

# Solid Seams and Thread Safety

# SOLID Seams and Thread Safety

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95 — "Distributed engine and SOLID refactor", plan 1 of 7.

## What we are trying to achieve

Plan 1 of the distributed-engine epic (S1, S10 in `docs/decisions/decisions-on-distributed-engine-and-solid-refactor.md`). Introduce the seams the rest of the epic builds on, about 80% SOLID rather than pedantic and in a functional style: an `EventBus` port (Redis and in-memory), `Clock` and `Process` ports, and an `AgentAdapter` capability contract. Then audit shared mutable state for thread safety: frozen `Data` by default, a `Mutex` or `Concurrent::Map` only where one is needed. No broad renames.

## Why it matters

The journal, recovery, watchdog and multi-node UI plans all need to swap the bus, the clock and the process layer under test, and to run more agents concurrently without races.

## What already exists

Facades per namespace; `Live::Store`/`MemoryStore`; `Adapters::Base` with claude, codex, pi; `Claims` already mutex-guarded.

## How to tell it's working?

- Engine, Live and Web publish and subscribe only through `EventBus`.
- Every adapter declares its capabilities, and the Executor branches on capabilities, never on adapter names.
- A thread-safety inventory of shared state is written down, and a stress spec runs N concurrent dispatch ticks green.
- Runs alone under the global lock (034).

## Framing

- **A. Port-first.** Add four named ports (`EventBus`, `Clock`, `Process`, `AgentAdapter` capabilities), move call sites onto them, then audit state.
- **B. Audit-first.** Inventory shared mutable state, fix races, and add ports only where the audit needs a seam.
- **C. Test-seam-first.** Add only what the stress spec needs to run deterministically.

**Chosen: A.** Decision S10 fixes the scope as four seams plus an audit, and the later plans (journal, recovery, watchdog, remote UI) need the seams to exist before they can swap them under test.

## Goal

After this ships, one `EventBus` port (Redis and in-memory implementations) carries every publish and subscribe from Engine, Live and Web. `Clock` and `Process` ports let a test control time and child processes. Every adapter declares its capabilities, and the Executor and Dispatcher read those, not names. A written inventory of shared mutable state, plus a stress spec running concurrent dispatch ticks, shows the engine is safe to run more agents at once. Later plans can swap bus, clock and process layer without touching engine logic.

## Non-Goals

- No broad renames and no broad SOLID sweep; that is plan `045.00` (decisions doc, S10 and the `045.00` note).
- No journal, recovery, watchdog or remote UI; those are plans 7, 3, 4, 5, 6 of the epic.
- No change to the Redis key layout, stream cursors or the wire format of the news nudge (`live/news.rb:25-27`).
- No new adapters and no change to what claude, codex or pi do.
- No replacement of `Execution::Clock` (the timeout timer, `execution/clock.rb:14`); the new `Clock` port is a time source, a different thing.
- No building of the global lock (034).

## In scope

Each item has its check.

1. `Live::EventBus` port: `publish`, `subscribe`, `xadd`-style durable append, with `RedisBus` and `MemoryBus`. Check: `rg "store\.(publish|subscriber|xadd)" lib` finds hits only inside the bus implementations.
1. `Live::News`, `Live::Publisher`, `Live::Commands`, `Web::Demo` and the web server call the bus only. Check: the same `rg` above, plus the existing Live and Web specs pass on `MemoryBus`.
1. A contract spec run against both bus implementations (shared examples). Check: it passes for both.
1. `Clock` port (`now`, `sleep`) with a system and a fake implementation; the Dispatcher's `Time.now` calls (`engine/dispatcher.rb:660`, `:860`, `:1274`, others) go through it. Check: `rg "Time\.now" lib/openlanes/engine` is empty; a dispatcher spec advances a fake clock.
1. `Process` port (`spawn`) used by `execution/child.rb:52`, `web/launcher.rb:105`, `vcs/refresh.rb:152`. Check: `rg "Process\.spawn" lib` finds only the system implementation; a spec runs `Child` on a fake.
1. `AgentAdapter` capability contract: each adapter declares `compacts?`, `resumes?`, `enforces_tool_denial?` and the compact prompt explicitly, from one `capabilities` value. Check: a spec iterates `Adapters` and asserts each declares all; `rg "adapter.*\.name ==|case .*adapter" lib/openlanes/{execution,engine}` is empty.
1. `lifecycle/brief.rb:215` stops naming `Adapters::Claude::LEAN` directly. Check: `rg "Adapters::Claude" lib` finds nothing outside `adapters/`.
1. Thread-safety inventory at `docs/thread-safety.md`: every shared mutable object under `lib/openlanes`, its owner, its thread(s), its guard or why none is needed. Check: a spec fails when a file creating a `Mutex` or `Concurrent::` object is not named in the document.
1. Each inventory finding is fixed: frozen `Data` by default, `Mutex` or `Concurrent::Map` only where the inventory says shared. Check: no open "unguarded" row in the document.
1. Stress spec: N concurrent dispatch ticks on `MemoryBus` and the fake clock, no exception, no lost or duplicated assignment. Check: runs green 20 times in a row.
1. Whole suite stays green and coverage stays at or above 95%. Check: `just ci`.

## Out of scope

- The global lock (034): unbuilt and depends on 033 (research, Q7). See open question 4.
- A Redis-less production mode: S-decisions put Redis in production; `MemoryBus` is for tests and `--demo`.
- Journal fsync and replay: owned by plan 7.
- Changes to how the Web UI renders: only its bus calls move.

## Back end / front end

| Item | Built by |
| :-- | :-- |
| 1-3 bus port, implementations, contract spec | `backend-coder` |
| 2 web server and `Web::Demo` call-site moves | `backend-coder`; `frontend-coder` only confirms the page's event stream still works (no page code changes) |
| 4-5 `Clock`, `Process` ports | `backend-coder` |
| 6-7 adapter capabilities | `backend-coder` |
| 8-9 inventory and fixes | `backend-coder` |
| 10 stress spec | `backend-coder` |

`frontend-coder` has no code to write. The browser sees the same SSE nudges; the check for them is the existing web specs and e2e.

## Open questions

Assumed defaults are stated so the planner can proceed; a human may overturn them.

1. **EventBus replaces or wraps `Live::News`?** Assumed: `News` stays as the nudge vocabulary (`KINDS`) and calls the bus; `Store`/`MemoryStore` become the bus implementations' backing. Fewest files move. (Research unsettled 1.)
1. **What is N, and what is a tick?** Assumed: N = 8 threads, each calling one full `Dispatcher` tick against a shared tree and fake clock; the assertion is that each plan is assigned at most once. (Research unsettled 2.)
1. **Does the inventory cover `execution/child.rb` subprocess handles?** Assumed yes: the handle is shared between the run thread and the timeout `Clock` thread. (Research unsettled 3.)
1. **Does 038 wait for 034's lock?** Assumed no: 038 does not build the lock, and the "runs alone" check is met by the operator running no other plan while it builds. This contradicts the criteria's wording and needs a human to accept. (Research unsettled 4.)
1. Does the `Process` port also cover `Open3`/backtick calls, or only `Process.spawn`? Assumed: only `spawn`, the three sites found; the planner should `rg` for others.
1. Where do ports live: a new `OpenLanes::Ports` namespace or inside `Live`/`Execution`? Assumed: `Live::EventBus` stays in `Live`; `Clock` and `Process` go in a small `support/` file pair, which Zeitwerk collapses.
1. The research counted 138 mutable-assignment sites as an upper bound only. The real audit size is unknown.

## Risks to planning or execution

- Contradiction with 034 (open question 4) can fail the last criterion if read literally.
- The Dispatcher is large (`dispatcher.rb:2102` is cited), so threading a `Clock` through it may touch many lines; keep the change mechanical.
- Moving `xadd` call sites onto a bus must not change stream ordering the web cursors rely on.
- Stress specs can be flaky; seed and bound them, and use the fake clock, not sleeps.
- The suite takes 4m21s (research Q6); budget for slow iterations.
- 80% SOLID scope creep: anything beyond the four seams belongs to `045.00`.

## Conclusion

When this ships, `Live::EventBus` with Redis and in-memory implementations is the only route for pub/sub and stream appends. `Clock` and `Process` ports exist and are used by the Dispatcher, `Child`, the launcher and refresh. Every adapter states its capabilities in one place and no engine code branches on an adapter name. `docs/thread-safety.md` lists every shared mutable object with its guard, a spec keeps it honest, and a concurrent-tick stress spec passes. Behaviour seen by users is unchanged.


## Research

Repository state: 2026-10-20, branch `kig/038.00-solid-seams-and-thread-safety`, clean. No external sources were needed.

### Questions answered

1. **Do Engine, Live and Web use one `EventBus` port?** No. The port does not exist (`rg EventBus lib` is empty). Pub/sub goes through `Live::News.publish` / `.subscribe` (`lib/openlanes/live/news.rb:45`, `:57`), which call `store.publish` and `store.subscriber` on either `Live::Store` (Redis) or `Live::MemoryStore` (`lib/openlanes/live/memory_store.rb:211`, `:220`). The two classes share a duck-typed interface, not a declared one (`lib/openlanes/live/store.rb:11-14`). Durable writes go straight to `store.xadd` from `live/publisher.rb:82`, `live/commands.rb:207` and `web/demo.rb:122`. The Engine's own store calls are zero: it reaches Redis only through `Live::Publisher`.
2. **Do adapters declare capabilities?** Partly. `Adapters::Base` has defaults, not a contract: `compact_prompt` nil (`lib/openlanes/adapters/base.rb:55`), `compacts?` (`:59`), `resumes?` false (`:66`), `enforces_tool_denial?` false (`:73`). Adapters are looked up by name in `lib/openlanes/adapters.rb:87`.
3. **Does the Executor branch on adapter names?** Not in the code I read. `executor.rb:810` branches on `compacts?`, and `.name` appears only in messages. `Engine::Dispatcher` branches on `resumes?` (`lib/openlanes/engine/dispatcher.rb:2102-2103`) and resolves the adapter through `adapter_of` (`:358-362`). One Claude-specific reference sits outside the adapter layer: `lib/openlanes/lifecycle/brief.rb:215` uses `Adapters::Claude::LEAN`.
4. **Are there `Clock` and `Process` ports?** No. Time comes from `Time.now` directly in the dispatcher (`engine/dispatcher.rb:660`, `:860`, `:1274`, and others). Process creation is direct `Process.spawn` at `execution/child.rb:52`, `web/launcher.rb:105` and `vcs/refresh.rb:152`. Partial injection exists: `MemoryStore` takes `clock:` (`memory_store.rb:17`), and `Dispatcher` takes `sleeper:` (`dispatcher.rb:134`). `Execution::Clock` (`execution/clock.rb:14`) is a timeout timer with its own thread, not a time source.
5. **Is shared state guarded?** Partly, and no inventory exists. 25 files under `lib/openlanes` create a `Mutex` or `Concurrent::` object. `Live::Claims` is guarded (`live/claims.rb:22`) and claims through `store.set(nx: true)` (`:34`). A raw count of `@x = []/{}/nil/0` assignments gives 138 sites. That is an upper bound on candidates, not an audit.
6. **Is the suite green before any change?** Yes. `bundle exec rspec` on the worktree, Ruby from `.ruby-version`: 3984 examples, 0 failures, 9 pending, 4m21s, coverage 98.81%.
7. **Is the global lock (034) there?** No. `034.00`'s spec says "nothing reads `execution:`". Plans run concurrently today.

### Contradictions

- The spec says "publish and subscribe only through `EventBus`". The code has no such class. The nearest seam is `Live::News` over `Live::Store`/`MemoryStore`. Production runs the Redis `Store` path.
- The spec says the work "runs alone under the global lock (034)". 034 is unbuilt, and it depends on 033 (`034.00` `depends_on: ["033.00"]`). `docs/decisions/decisions-on-distributed-engine-and-solid-refactor.md:81-86` (S10) says plan 1 runs alone. Production today runs concurrently with no lock.
- The spec's "What already exists" says "`Adapters::Base` with claude, codex, pi". The adapters exist (`lib/openlanes/adapters/`), but the capability methods are defaults, not a declared contract (see 2).
- The draft repeats four headings with empty bodies (`## What we are trying to achieve`, `## Why it matters`, `## What already exists`, and the title line `# Solid Seams…`). This is a draft defect, not a conflict in the system.

Production runs the code above: Redis-backed `Store` where configured, `MemoryStore` in tests, no global lock, no `EventBus`.

### Findings, Conclusion & References

**Findings.** The seams the spec names half-exist. Pub/sub, the store and the clock/sleeper injection exist in pieces. The capability contract, `EventBus`, the `Clock`/`Process` ports and the thread-safety inventory do not.

**Conclusion.** The work is buildable. Its scope is the four ports plus the audit. The global-lock dependency on 034 must be settled before the "runs alone" check can pass.

**Unsettled (for spec-writer to lift into open questions):**

1. Does `EventBus` replace `Live::News` or wrap it? Both are workable; the choice changes which files move.
2. What is N in the stress spec, and what counts as one "dispatch tick" under concurrency?
3. Does the thread-safety inventory cover only `lib/openlanes` or also the adapter subprocess handles (`execution/child.rb`)?
4. Does 038 start before 034's lock exists, or does 038 build the lock as part of its own scope?

**Sources.** Repository files and commands only. Decisions: `docs/decisions/decisions-on-distributed-engine-and-solid-refactor.md` (S1, S10). Test run: 2026-10-20, output above. No external sources were consulted; none are paywalled or licensed.

