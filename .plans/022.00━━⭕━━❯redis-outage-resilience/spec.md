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

## Research

Anchors are `file:line` in the worktree at `7186635`, or a command with its output. No external source was used.

### Answers

1. **Which tick paths survive a Redis drop?** By reading, the tick survives. Every Redis call goes through `Store#guarded`, which maps `RedisClient::Error` to `Live::Unavailable` (`lib/openlanes/live/store.rb:267-273`). Each caller rescues it: `Publisher#call` (`live/publisher.rb:92`), `RunRecord#flush` and `#read_redis` (`live/run_record.rb:75`, `:118`), `Commands#call` (`live/commands.rb:97`), `Dispatcher#drain_mail` (`engine/dispatcher.rb:1081`), `Runner#foreign?` and `#claim` (`engine/runner.rb:140`, `:154`), `Session#close` (`live/session.rb:101`). `rg RedisClient lib` finds the client only in `store.rb` and `subscriber.rb`, and the subscriber wraps its calls in `guarded`. So the code does not show where #59's shutdown comes from. Start-up is covered too: `Live.connect` (`live.rb:51-55`) falls back to a headless run (`engine/run_workflow.rb:247`).
2. **How do agents pause?** Nothing exists for outages. `Execution::Control` already broadcasts `WRAP_UP`, `STOP`, `INTERRUPT`, `WARN` and `HOLD` to each agent's control file (`execution/control.rb:19-38`, `:93-122`). `HOLD` means a person wants to talk, so do not reuse it for a pause. Recommendation (technical): add a `PAUSE` word to the same broadcast. Running agents finish their invocation, and the dispatcher assigns nothing new, the way `Dispatcher#resting?` (`engine/dispatcher.rb:747`) already holds back new work.
3. **Backoff parameters.** The repo fixes none. The store uses `reconnect_attempts: 1` and `TIMEOUT = 2.0` (`store.rb:44`, `:71`). Measured, a `Store` answers again on the same object after Redis restarts (see Experiment). So the loop only paces probes and need not rebuild the client. Values are a tuning choice: see Could not settle.
4. **Heartbeat write load.** Each tick already writes three keys in one `MULTI`: snapshot, board stream and this node's `nodes` hash field (`live/publisher.rb:80-84`). That field carries `heartbeat_at` (`live/node.rb:40`). The last-alive time the plan asks for already exists per node, so a separate key would duplicate it. A clean exit deletes the field (`live/session.rb:100`), which is correct because a clean exit has no outage. A crash keeps it.
5. **AOF or empty restart.** The epoch cannot tell them apart alone: under RDB, a restart from an older snapshot rolls the epoch key back with the data. Local Redis 8.8.0 is RDB-only: `aof_enabled:0`, `rdb_last_bgsave_status:ok` (`redis-cli INFO persistence`, run 2026-10-16), and `save 3600 1 300 100 60 10000` in `/opt/homebrew/etc/redis.conf`. Target installs are not in the repo.
6. **Reconcile from file or trust Redis.** Already decided by code. `RunRecord#restore` takes the copy with the higher `seq` (`live/run_record.rb:53`), and `mirror` keeps `.plans/openlanes-state.json` current (`run_record.rb:102-108`). Redis restarted empty, or from an older snapshot, loses on `seq`, so the file wins.

### Contradictions

- The plan says the engine "shuts down", and `dispatcher.rb:1081` is named as the place to check. That rescue covers only mail. The tick has no shutdown path in the code read here, so the #59 claim is unreproduced.
- The plan says `Live::Subscriber` "has no reconnect". `live/chat.rb:160` does retry: it closes the subscription and opens a fresh one on the next step, with one warning per outage. The plan is right about the class and wrong about the feature.
- The plan proposes a new per-repo epoch key. `nodes` already holds `heartbeat_at` per node (answer 4). Production runs the code on `main`, so the existing field is what a restart would read.

### Experiment

Throwaway Redis on port 6390, not the user's Redis on 6379. Script `/tmp/leah-outage.rb`, not in the repo:

```
up     ping: true
down   ping: OpenLanes::Live::Unavailable: Redis at redis://127.0.0.1:6390/0 is unavailable: Connection refused
down   hgetall: OpenLanes::Live::Unavailable: ... Connection refused
back   ping (same Store): true
back   set: true
```

`bundle exec rspec spec/openlanes/engine/dispatcher_spec.rb spec/openlanes/engine/stay_spec.rb spec/openlanes/live spec/openlanes/live_spec.rb` exits 0 (`/tmp/leah-rspec.txt`).

### Could not settle

1. Why the engine shut down in #59. Needs `openlanes run` with Redis stopped mid-run, which was not done.
2. Backoff initial delay, cap and jitter. Recommendation for yoda to put to a human: 1 s initial, 30 s cap, full jitter.
3. Persistence on target installs (AOF or RDB). Not in the repo.
4. Whether `PAUSE` freezes agents or lets them finish. Recommended: finish, do not freeze.
5. Loss window. The epoch rolls back with RDB data, so it cannot measure loss by itself. Needs a decision on whether the file's `seq` or the engine's own clock bounds the window.

### Findings, Conclusion & References

- Findings: the tick is guarded on every Redis path by reading. #59's shutdown is unlocated. Agents have a control-file channel to reuse for `PAUSE`. The epoch already exists as `nodes[].heartbeat_at`. Reconciliation by `seq` already exists.
- Conclusion: the work is mostly a reproduction of #59, then a `PAUSE` word and a backoff loop. A new epoch key is not needed.
- References: repo anchors above; `redis-cli INFO` output above; no external URLs.


## Framings

1. **Resilience by pause.** A Redis outage is a known state: the engine stops assigning work, tells agents, probes with backoff, and resumes. Matches the issue's text.
1. **Resilience by indifference.** Redis is already optional (`Live::Unavailable` is rescued on every path, research answer 1), so do nothing but prove it. If a real shutdown cannot be reproduced, there is nothing to pause for.
1. **Resilience by durable truth.** Make `.plans/openlanes-state.json` the source and Redis a mirror, so an outage never matters (overlaps plan 020.00).

**Chosen: 1, gated by 2.** The issue asks for pause and backoff, and the research found no code path that shuts the engine down (`lib/openlanes/live/store.rb:267-273` maps every client error). Reproduction comes first; pause and backoff are built only on the failure it shows. Framing 3 belongs to plan 020.00.

**Tightened problem.** On a Redis drop the engine should pause new work, tell running agents, and probe Redis on a capped exponential backoff until it answers. On return it reports the outage length from the existing `nodes[].heartbeat_at` field (`live/publisher.rb:84`) and reconciles run state by `seq` (`live/run_record.rb:53`). A new per-second epoch key is dropped: the field already carries the last-alive time (research answer 4).

## Goal

After this ships, a Redis outage of any length pauses `openlanes run` instead of ending it. The engine stops assigning plans, running agents finish their invocation and are told a pause is on, and the engine resumes by itself once Redis answers, logging how long it was gone and whether run state was reconciled from the file.

## Non-Goals

- Making Redis highly available (Sentinel, cluster, replicas).
- Freezing or killing running agents on an outage; they finish (research, Could not settle 4).
- A second heartbeat key; `nodes[].heartbeat_at` is reused.
- Detecting or repairing data lost under RDB; only reporting the outage window.
- A durable event sink; that is plan 020.00.
- Changing the `Live::Unavailable` contract for headless runs.

## In scope

Each item has its check.

1. **Reproduce #59.** A recorded `openlanes run` with Redis stopped mid-run, with the exit status and the line that raised. Check: the finding is written into `plan.md` or the PR, and a spec fails before the fix.
1. **Outage state in the engine.** A paused flag set when a guarded Redis call raises `Unavailable`, cleared on a successful probe. Check: unit spec drives a `MemoryStore` double that raises, then recovers; the flag flips both ways.
1. **No new assignments while paused.** Check: dispatcher spec shows no agent assigned during the pause and assignment resuming after it, using the `resting?` pattern (`engine/dispatcher.rb:747`).
1. **`PAUSE` control word.** Added to `Execution::Control` (`execution/control.rb:19-38`) and broadcast to live agents' control files; cleared on resume. Check: control spec reads the word from the file; the agent prompt explains it. It is not `HOLD`.
1. **Backoff probe loop.** Initial, cap and jitter configurable, default per Open question 1. Check: spec with an injected clock and random source asserts the delay sequence and the cap.
1. **Resume report.** On recovery, one log line gives outage duration (from `heartbeat_at`, falling back to the engine's own monotonic clock) and which side won the `seq` reconcile. Check: spec asserts the line for both RDB-rollback and no-loss cases.
1. **A real-Redis outage spec.** Stops and restarts a throwaway Redis on a spare port, as leah's experiment did, and asserts the same `Store` answers again. Check: spec passes; skipped with a stated reason when no `redis-server` binary exists.
1. **Docs.** README states the outage behavior and the knobs. Check: `openlanes docs` still regenerates cleanly; `just lint` and `just test` are green.

## Out of scope

- Redis HA or persistence tuning: the operator owns it; the repo cannot see target installs.
- AOF versus RDB detection: not derivable from the client without `CONFIG GET`, which managed Redis often forbids (open question 3).
- Subscriber/chat reconnect: `live/chat.rb:160` already retries.
- Linear and GitHub outages: different seams.

## Back end / front end

| Item | Builds it |
| :-- | :-- |
| 1 Reproduce #59 | `luke-backend` |
| 2 Outage state, 3 no assignments, 5 backoff, 6 resume report | `luke-backend` |
| 4 `PAUSE` word | `luke-backend` for the file and broadcast; `rey-frontend` shows a "paused" banner on the board page and renders the new command word if the page lists control words |
| 7 Real-Redis spec, 8 Docs | `luke-backend` |

`rey-frontend`'s part is small and optional on the board snapshot: a `paused` field added to the snapshot in `live/publisher.rb` that the page shows. Pair them on that field's name. The snapshot cannot be written during an outage, so the page shows the last snapshot's age; this is open question 5.

## Open questions

1. **Backoff values.** Recommended: 1 s initial, 30 s cap, full jitter (leah). A tuning choice, not verified against any workload.
1. **Why #59 shut the engine down.** Unreproduced; the plan may shrink or change shape once item 1 runs. If it cannot be reproduced, is shipping pause and backoff still wanted?
1. **Persistence on target installs.** Unknown. Local Redis is RDB-only (`aof_enabled:0`, research answer 5). The spec reports the window and does not branch on the mode.
1. **Loss window bound.** `heartbeat_at` rolls back with an RDB snapshot, so it cannot measure loss alone. Item 6 assumes the engine's own clock backs it up.
1. **Paused banner.** The snapshot is written to Redis, so a paused engine cannot publish "paused". Assumed: the page infers it from a stale snapshot.
1. **Maximum outage.** Assumed: pause forever, no give-up timeout. Nothing in the repo says otherwise.
1. **Overlap with plan 020.00.** Both touch what Redis lost; assumed independent, with this one reading only the existing fields.

## Risks to planning or execution

- Item 1 may find the shutdown is not in the Redis path at all (for example a rescue missing outside `Live`), which changes the work. Plan item 1 as the first unit with a gate.
- `PAUSE` for agents that never read their control file does nothing; the Executor's after-check cannot force it. Expect partial effect.
- A paused dispatcher must still drain commands and run the clock, or `STOP` and Ctrl-C stop working during an outage. `Commands#call` needs Redis, so Ctrl-C during an outage must keep working through the local path.
- Timing specs against real Redis are flaky if ports clash; use an ephemeral port.
- Shared `Store` across threads while a probe runs: not examined in the research.

## Conclusion

Redis dropping mid-run pauses the engine rather than ending it. Agents are told with a `PAUSE` word through the existing control file and finish their current invocation. A backoff probe resumes the run, and a log line gives the outage length and which copy of run state won. No new Redis key is added. The first step is a recorded reproduction of #59, since the code read so far has no shutdown path.
