---
created: 2026-10-16
lane: full
---

# Redis Outage Resilience

Source: GitHub issue #59, https://github.com/kigster/openlanes/issues/59 — "Resilience to Red Is going dowm"

If Redis disappears for a second, the entire system goes down. The engine shuts down. This is not a correct behavior. 

What the engine should do if the connection to Redis has been interrupted or disappeared is to pause operation and notify the agents to pause operation as well. Then it should start a loop that attempts to reconnect to Redis on an exponentially backing off frequency. 

Eventually, when it reconnects to Redis, there could be some sort of a check in terms of how behind is Redis compared to when it went down. To get there, the dispatcher should probably write an epoch timestamp to Redis every second for a very specific given key—the key that incorporates the user and the host and the repo. When Redis boots, you will read that key and it'll contain the second Redis went down. And therefore, you will know exactly how much time had passed and what Redis had lost. 

A thing to consider is that Redis will lose data only if it's in RDB save mode, and if it's in AOF, it wouldn't lose any data because it'll load it upon booting.

## What we are trying to achieve

- A Redis blip pauses the engine instead of killing it, and the agents pause with it.
- The engine retries the connection on an exponential backoff until Redis answers again.
- A heartbeat epoch key, scoped to user, host and repo, lets the engine on reconnect measure how long Redis was down and what it may have lost.
- Data loss is only a concern under RDB persistence; AOF replays on boot.


## Why it matters

Today a Redis disappearance takes the whole engine down (issue #59). The repo already treats Redis as optional for runs (`engine/runner.rb`, `engine/dispatcher.rb` and `live/run_record.rb` all rescue `Live::Unavailable`), so a single dropped connection should not be fatal. Nothing in the repo says how long Redis may be gone before that stops being acceptable.


## What already exists

- `lib/openlanes/live/store.rb` (`Live::Store`): the single Redis connection wrapper. It uses `RedisClient` with `reconnect_attempts: 1`, a short timeout so a hung Redis does not hang the tick, and maps every connection failure to `Live::Unavailable`. No backoff loop exists yet.
- `lib/openlanes/live/subscriber.rb`: a pub/sub connection that raises `Unavailable` on failure; no reconnect.
- `lib/openlanes/engine/dispatcher.rb` (around line 1081): rescues `Live::Unavailable` and `SystemCallError` in the tick loop. The issue says the engine still shuts down, so check this path first.
- `lib/openlanes/engine/runner.rb` (lines 140 and 154): also rescue `Live::Unavailable`.
- `lib/openlanes/live/run_record.rb`: keeps `RunState` in Redis and mirrors it to `.plans/openlanes-state.json`. It reconciles on read by `seq`, so it is the closest existing answer to "what did Redis lose".
- `lib/openlanes/live/repo.rb`: builds the `github.com/<owner>/<name>` identity used in Redis keys. This is the natural source for the user, host and repo key the heartbeat needs; the host part does not exist yet.
- `lib/openlanes/live/memory_store.rb`: an in-memory store with the same surface, usable in specs.
- Related plan `.plans/020.00━━⚪━━❯durable-run-events/`: proposes a durable event sink beyond Redis. It overlaps with the "what Redis lost" question.
- `lib/openlanes/apps/runner.rb` (around line 158): another `Live::Unavailable` path, for apps.


## What research needs to settle

- Which exact tick paths keep running today when Redis drops, and which ones still raise. Not verified by reading alone.
- How agents are told to pause. The repo has no pause signal yet, so the mechanism is open.
- Backoff parameters: initial delay, cap, and jitter.
- Whether the one-second epoch heartbeat is acceptable write load on a shared Redis, and whether it should be a plain key or part of `RunRecord`.
- How the engine can tell "Redis restarted with AOF" from "Redis restarted empty" beyond comparing the epoch. Confirm the persistence config on the target installs.
- Whether a reconnect after a long outage should reconcile from `.plans/openlanes-state.json` or trust Redis.

