# Decisions on the distributed engine and SOLID refactor

Decided 2026-10-19 by the owner (kig), in a grilling session.
Tracked in GitHub issue #95.

The ask: refactor toward SOLID (about 80%, not pedantic), functional style, and thread safety. Remove vendor lock-in with adapters for Claude, Codex, Gemini and Grok. Make the engine fault tolerant and self-healing, with a machine-readable journal so it can resume after a crash. Guarantee that no plan can stall. Keep the UI in sync over pub/sub. Support many Sinatra back ends on many machines, plus one authoritative UI that controls all of them.

What already exists and is built on, not replaced: the Redis live store, the `engine` consumer-group command stream (W13), node identity and plan claims (W26), and outage pause with backoff (W32).

### S1. An epic of seven plans, not one

Each plan gets its own `.plans` folder and pull request:

1. SOLID and facade refactor, plus a thread-safety audit.
1. Adapter port, with Gemini and Grok adapters next to Claude, Codex and Pi.
1. Idle on start, plus PID-verified crash recovery.
1. Stuck-plan watchdog: extend the time, then ask a person.
1. Client registry, plus a per-node UI that shows other nodes read-only.
1. Authoritative UI: one Redis slot, bidirectional pub/sub with every engine.
1. Machine-readable progress journal.

Overlapping plans: `021` (runtime state outside plans), `022` (Redis outage resilience) and `027` (agent asks for more time) fold into this epic. `020.01` (durable run events) stays a separate plan.

### S2. The authoritative UI does not demote the per-node UIs

- A per-node UI keeps full control of its own node, even while the authoritative UI holds the slot.
- Commands from both go through that node's existing command stream, so the order is the order they arrive in, and the last one wins.
- Every reply names the client that sent the command, and every connected UI sees every command and reply.

### S3. The authoritative slot is a renewed lease that can be taken over

- `openlanes web --authoritative` takes the slot with `SET NX EX 30` and renews it every 10 seconds. The lease expires 30 seconds after its holder crashes.
- A second `--authoritative` UI is refused at startup and told who holds the slot.
- `--take-over` evicts the current holder. The evicted UI is told so and drops to per-node mode.

### S4. Agents outlive the engine and are re-attached through files

- An agent writes stdout to a per-run NDJSON file, not to a pipe the engine owns. It runs in its own session, so it outlives an engine crash.
- The run journal records each agent's PID, process start time, session id, output file and the last offset read.
- On restart, the engine keeps a PID only when it is alive and its start time matches, which rules out a reused PID. It then tails the file from the recorded offset.
- "Responds back" means the PID is alive and its output file is still growing. `claude -p` cannot answer a ping, so a control-file ping is only advisory.
- A dead agent is resumed with `--resume <session>` where its adapter supports it (`Adapter#resumes?`), and otherwise gets a fresh round.

### S5. The watchdog has two triggers and a three-step ladder

- **Triggers.** The clock running low, or a stall: no agent output and no worktree change for `stall_minutes` (default 10).
- **Ladder.**
  1. Ask the agent whether it needs more time, granting 5-minute chunks up to 30 minutes in total, as in `027` (M4).
  1. Interrupt and resume the session in a new round, at most twice.
  1. Open a `blocked.md` question for a person, quoting the agent's last output and naming any plan it conflicts with.
- **Invariant.** Every plan in flight is either progressing, waiting on a person, or terminal. A plan waiting on a person is never counted as stuck. A spec asserts that no other state can be reached.

### S6. Remote UIs use HTTP plus SSE, a client registry, and a cluster token

- A UI reaches a back end on another machine at `--api-url`. Commands go over HTTP. Updates come over Server-Sent Events, relayed from Redis pub/sub, the same mechanism the page uses today.
- Each UI registers with `POST /clients` and gets a unique client id. A heartbeat keeps it alive in Redis under a TTL. Every client gets the same updates.
- Auth is one shared bearer token per cluster, kept encrypted with sopsy.
- The back ends are meant for a trusted LAN or tailnet. The app does not terminate TLS.

### S7. Only `openlanes start` comes up idle

- `openlanes start` (engine plus web) comes up idle. The one exception is when the journal shows plans in flight on this node: those are resumed under S4.
- The page gets Start All, Start plan and Stop. The authoritative UI can send any of them to any node.
- `openlanes run` (the headless CLI) starts processing at once, since nothing else could ever start it.
- `openlanes start --autostart` restores today's behavior.

### S8. Gemini and Grok get adapters for their official CLIs

- Targets: Google's `gemini` CLI in headless stream-json mode and xAI's `grok` CLI in its headless JSON mode. Both are installed on the owner's machine.
- Each adapter declares what it can do: resume, tool deny-lists, its stream format. The Executor degrades where a capability is missing. With no deny-list flag, for example, the Boundary after-check is the only guard.
- Specs run against recorded transcripts. Nothing calls the network.

### S9. The journal is an NDJSON file per node, mirrored to Redis

- Each node keeps an append-only NDJSON journal in `.openlanes/journal/`, a git-ignored runtime directory, as `021` proposed.
- Each line is one event, fsync'd and schema-versioned.
- The file is the source of truth for recovery, so it survives a Redis outage or data loss. Recovery replays it.
- Each event is also published over Redis pub/sub so the UIs stay in sync.
- `020.01` can later ship the journal into Postgres.

### S10. The refactor builds seams first, and the plans run in a fixed order

- **Plan 1 stays narrow.** It adds four seams and changes nothing else:
  - an `EventBus` port with a Redis and an in-memory implementation,
  - a `Clock` and `Process` port,
  - an `AgentAdapter` capability contract,
  - an audit of shared mutable state: frozen `Data` by default, and a `Mutex` or `Concurrent::Map` only where one is needed.

  No broad renames.
- **Order.** 1 seams, 7 journal, 2 adapters, 3 recovery, 4 watchdog, 5 registry and remote UI, 6 authoritative UI.
- **Plan 1 runs alone.** It touches more than half the files, so it takes the global lock that `034` specifies.

### S11. One shared Redis, and no HTTP between nodes

- Every node and the authoritative UI use one Redis, reachable over the LAN or tailnet.
- Read-only views of other nodes come from that Redis. Back ends never call each other over HTTP, so `--api-url` is needed only when a browser points at a back end on another machine.
- No Redis Cluster or Sentinel. The S9 journal covers losing Redis.

### S12. Streams carry the data, pub/sub only wakes listeners

- Redis Streams, capped by MAXLEN, are the durable channel. A listener replays from an offset or from `Last-Event-ID`.
- Pub/sub only tells listeners that something new has arrived.
- Each node has a command stream. Each client has a `replies:<client_id>` stream, which carries one-to-one answers.

### S13. A command to an offline node waits, then expires

- A command for a node that is down waits in that node's stream.
- It is applied if the node returns within `command_ttl` (default 5 minutes).
- Past that, it is refused, and the sender gets an explicit "expired" reply.

### S14. A supervisor restarts crashed processes, and launchd or systemd keeps the supervisor alive

- `openlanes start` becomes a thin supervisor. It forks the engine and the web as children and restarts either one with backoff.
- After 5 crashes in 10 minutes it gives up loudly.
- `openlanes service install` generates a launchd (macOS) or systemd (Linux) unit that keeps the supervisor itself alive, including across reboots.

### S15. Threads come from concurrent-ruby, and errors travel as dry-monads results

- Agents are subprocesses, so the engine's threads only wait on I/O.
- The 24 bare `Thread.new` call sites move to `concurrent-ruby` primitives: `Concurrent::Map`, `TimerTask`, and a bounded `ThreadPoolExecutor`.
- A fallible operation returns a dry-monads `Result` instead of raising across a thread boundary.
- No Ractors and no Async (fibers).

### S16. One page for both roles, with controls gated by role

- There is one SPA build.
- The page reads its role (`node` or `authoritative`) and its capabilities from `GET /api/whoami`.
- It shows or hides the cluster-wide controls to match. The authoritative page is a superset of the node page.

### S17. The question goes to both UIs, the first answer wins, and nobody answering is waiting, not stuck

- The watchdog's question is pushed to the node's local UI and to the authoritative UI.
- The first answer wins. The other UI sees the question closed, along with who answered it.
- If nobody answers, the plan stays ⭕ indefinitely. That is waiting on a person, not stuck.
- The board shows how long the question has waited. After `notify_after` (default 1 hour) the node sends a local desktop notification. No email and no Slack.

### S18. Conflicts are found by file overlap and explained by Jev

- **Detection** is deterministic. It compares the files this plan's worktree diff touches with those touched by other in-flight plans' diffs and planned in their `plan.md` work units.
- **Explanation.** When something overlaps and `TYPESAFE_API_KEY` is set, TypeSafe's Jev gives a typed "do these contradict?" judgment plus an explanation for the person.
- **Fallback.** If `TYPESAFE_API_KEY` is unset, or Jev fails or times out, the project's default adapter explains it with its cheapest model. If that fails too, the question goes out with the file overlap alone.
- **Before building:** under rule R5, read TypeSafe's terms and privacy policy, since plan diffs would leave the machine. Report anything unusual to the owner first.

### S19. A SOLID sweep follows the seams, and Jev is optional behind TYPESAFE_API_KEY

Decided 2026-10-20.

- A new plan, `045.00` solid-sweep, does the broad ~80% SOLID pass that S10 left out of `038`: one responsibility per class, collaborators injected through the `038` ports, facade-only access between namespaces, a functional core, and the S15 move to concurrent-ruby and dry-monads.
- It depends on `038` and runs alone under the global lock.
- It adds a vendor-neutral `Judgment` port. Jev is one backend, used only when the `TYPESAFE_API_KEY` environment variable is set. Without it, nothing loads or calls TypeSafe, and the default adapter answers.
- `042` (the watchdog) now depends on `045` as well, because its conflict explanation goes through `Judgment`.

## Plan folders

| Epic step | Plan | Depends on |
| --- | --- | --- |
| 1 seams | `038.00` solid-seams-and-thread-safety | none |
| 7 journal | `039.00` progress-journal | 038 |
| 2 adapters | `040.00` gemini-and-grok-adapters | 038 |
| 3 recovery | `041.00` idle-start-and-crash-recovery | 039 |
| 4 watchdog | `042.00` stuck-plan-watchdog | 041, 045 |
| 5 registry | `043.00` client-registry-and-remote-ui | 039 |
| 6 authority | `044.00` authoritative-control-room | 043 |
| 8 sweep | `045.00` solid-sweep | 038 |

`040` and `043` can run beside the `041`→`042` chain once their dependencies land.
