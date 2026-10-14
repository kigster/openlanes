# 012.00 App Runner and Preview, back end

`luke-backend` builds these. Namespace is `OpenLanes::Apps` (`lib/openlanes/apps.rb` facade, `lib/openlanes/apps/`), plural like `Agents` and `Adapters`, so it never collides with `Web::App`. B1 lands first: `rey-frontend` builds against its event shape.

## B1 Contract: `app:` config and the status event

- **Discipline:** back end
- **Covers spec items:** 1, 2, 9
- **Owns:**
  - `lib/openlanes/support/config.rb` (accept `app:`, add to `KEYS`, refuse unknown keys inside it, as `config.rb:125-128` does)
  - `lib/openlanes/apps.rb` (facade: `Apps.definition(config)`, `Apps.supervisor(...)`, `Apps.registry`)
  - `lib/openlanes/apps/definition.rb`: `Definition = Data.define(:kind, :processes)`, `ProcessSpec = Data.define(:name, :start, :ready, :restart_on, :preview)`; `Definition#preview` returns the one preview process or `nil`; `ProcessSpec#port_env` returns `PORT_<NAME>` (upcased, non-alphanumerics to `_`)
  - `lib/openlanes/apps/status.rb`: `Status = Data.define(:plan, :branch, :process, :state, :port, :preview, :url, :framing, :reason, :at)`, `STATES = %w[starting ready restarting stopped failed]`, `#to_h` is the wire payload below
  - `lib/openlanes/live/keys.rb` (two new keys: `apps(machine = node id)`, a hash `openlanes:<repo>:apps:<node id>` of plan to its statuses and heartbeat; `app_commands(machine = node id)`, the stream the page's buttons go to)
  - `lib/openlanes/apps/listing.rb`: `Apps::Listing.read(store:, keys:, now:)` returns every live `<app>` hash on this machine, pruning plans whose heartbeat is older than `Listing::TTL` (30 s); `Listing.write(store:, keys:, plan:, statuses:)` and `Listing.remove(store:, keys:, plan:)`
  - `lib/openlanes/web/events.rb` (an `apps` snapshot on stream open, then one `app` event for each process whose status changed since the last tick)
  - specs: `spec/openlanes/config_spec.rb`, `spec/openlanes/apps/definition_spec.rb`, `spec/openlanes/apps/status_spec.rb`, `spec/openlanes/apps/listing_spec.rb`, `spec/openlanes/web/events_spec.rb`
- **Must not touch:** anything under `web/`, `lib/openlanes/execution/`, other `lib/openlanes/apps/*` files
- **Depends on:** nothing
- **Done when:** `config_spec.rb` loads a valid `app:` and refuses an unknown key inside it and a process missing `name` or `start`, each with the file named; `definition_spec.rb` refuses two `preview: true` and returns `nil` for zero; `listing_spec.rb` round-trips statuses and prunes a stale heartbeat; `events_spec.rb` sees the `apps` snapshot on open and one `app` event per changed process.

Wire shape, fixed here and copied by `rey-frontend` into `web/src/api/types.ts`:

```
event: apps   data: { "apps": [ <app>, ... ] }        # on stream open, latest per (plan, process)
event: app    data: <app>                              # every transition

<app> = { "plan": "012.00", "branch": "kig/012.00-...", "process": "web",
          "state": "starting|ready|restarting|stopped|failed",
          "port": 11101, "preview": true, "url": "http://127.0.0.1:11101/",
          "framing": "frame|window|null", "reason": "string|null", "at": "ISO-8601" }
```

`framing` is `null` until the preview process is ready, and is set only on the preview process. `reason` carries the failure message (item 6, 7).

Config shape:

```yaml
app:
  kind: web               # free text, recorded, not interpreted
  processes:
    - name: api
      start: bin/rails s -p $PORT_API
      ready: /up          # optional HTTP path; absent means TCP only
      restart_on: ["app/**/*.rb", "config/**/*"]
    - name: web
      start: npx vite --port $PORT_WEB --strictPort
      ready: /
      preview: true
```

## B2 Port registry

- **Discipline:** back end
- **Covers spec items:** 3, 4
- **Owns:** `lib/openlanes/apps/ports.rb`, `spec/openlanes/apps/ports_spec.rb`
- **Must not touch:** `config.rb`, `supervisor.rb`, `web/`
- **Depends on:** nothing
- **Done when:** `ports_spec.rb` shows two reservations get 11100 and 11101; a port held by a live `TCPServer` is skipped; two registries rooted in different directories but sharing one file get disjoint ports; an entry whose owner pid is dead is reclaimed; `release_owner` frees every port it held.

Planner decisions (spec open question 2):

- **File:** `${XDG_STATE_HOME:-~/.local/state}/openlanes/ports.json`, overridden by `OPENLANES_PORTS_FILE` (specs point it at a tmpdir). One file per machine, guarded by `File#flock(LOCK_EX)` for each read-modify-write.
- **Entry:** `port => { owner_pid, root, plan, process, at }`. An entry whose `owner_pid` is not alive is free.
- **API:** `Ports.new(path:)`, `#reserve(root:, plan:, process:) -> Integer`, `#release(port)`, `#release_owner(pid = Process.pid)`.
- **Range:** 11100 to 11999; exhausting it raises `Ports::Exhausted`. Not configurable (non-goal).
- **Race:** a reservation is also probed by binding 127.0.0.1; the supervisor (B4) retries once with a fresh reservation on `EADDRINUSE` during start.

## B3 Probes: readiness and framing

- **Discipline:** back end
- **Covers spec items:** 5 (the check itself), 11
- **Owns:** `lib/openlanes/apps/probe.rb`, `lib/openlanes/apps/framing.rb`, `spec/openlanes/apps/probe_spec.rb`, `spec/openlanes/apps/framing_spec.rb`
- **Must not touch:** `supervisor.rb`, `config.rb`, `web/`
- **Depends on:** nothing
- **Done when:** `probe_spec.rb` passes against a real `TCPServer` (connect, 2xx, 3xx ready; 4xx, 5xx, refused not ready); `framing_spec.rb` covers `X-Frame-Options: DENY`, `SAMEORIGIN`, `frame-ancestors 'none'`, `frame-ancestors 'self'`, `frame-ancestors http://127.0.0.1:11000` (frames), and no header (frames).

Signatures:

- `Probe.ready?(port, path: nil) -> Boolean`: TCP connect to 127.0.0.1:port, then, when `path`, a GET answering 2xx or 3xx. Net::HTTP, 1 s open and read timeouts.
- `Framing.verdict(headers, origin:) -> :frame | :window`: pure, on a header hash.
- `Framing.check(url, origin:) -> :frame | :window`: one GET of the preview path, then `verdict`. `origin` is the control room's (`http://127.0.0.1:11000`, from `Web`).

## B4 Supervisor: ordered start, failure, port check, stop

- **Discipline:** back end
- **Covers spec items:** 5, 6, 7, 9 (emits), 11 (calls), 12
- **Owns:** `lib/openlanes/apps/supervisor.rb`, `spec/openlanes/apps/supervisor_spec.rb`, `spec/fixtures/apps/servers/` (tiny Ruby servers: one that answers, one that records when its sibling first answered, one that binds a port other than its `PORT_*`, one that exits, one that never listens)
- **Must not touch:** `lib/openlanes/execution/child.rb` (use it, do not change it), `ports.rb`, `probe.rb`, `framing.rb`, `web/`
- **Depends on:** B1, B2, B3
- **Done when:** `supervisor_spec.rb` shows: the second process starts only after the first is ready (recorded timestamp); every process sees every `PORT_<NAME>`; a process that exits or misses the timeout fails the start, stops its started siblings and leaves no live child; the moved-port fixture fails with a reason naming the port it was given; `stop` leaves the ports free in the registry and connectable by a fresh `TCPServer`, and no child alive; each transition is published as a B1 `Status`.

Signatures:

- `Supervisor.new(definition:, root:, plan:, branch:, registry:, publisher:, probe: Probe, framing: Framing, clock:, sleeper:, ready_timeout: 30)`
- `#start -> self` (raises `Supervisor::StartFailed` with the reason, after stopping what it started), `#stop`, `#statuses -> Array<Status>`, `#preview -> Status | nil`
- Processes spawn through `Execution::Child.spawn(["sh", "-c", start], chdir: root, env:)` so the group kill reaches grandchildren.
- **Readiness timeout:** 30 s per process, a constructor argument and not a config key (spec open question 10).
- **Port honoured:** readiness is checked only on the allocated port, so an app that moved never becomes ready; its failure reason says `"<name> was given port N and nothing answered there"`.
- **Engine exit:** `#stop` is registered in `at_exit` by B6, and the registry's dead-pid reclaim covers a `KILL`.

## B5 Watcher and restart on change

- **Discipline:** back end
- **Covers spec items:** 8, 11 (re-check after restart)
- **Owns:** `lib/openlanes/apps/watcher.rb`, `spec/openlanes/apps/watcher_spec.rb`, `spec/openlanes/apps/restart_spec.rb`; also edits `lib/openlanes/apps/supervisor.rb` (adds `#restart(name)`)
- **Must not touch:** `ports.rb`, `probe.rb`, `config.rb`, `web/`
- **Depends on:** B4 (sequential: both write `supervisor.rb`)
- **Done when:** `watcher_spec.rb` drives the poller with an injected clock and sleeper and reports only the process whose glob matched; `restart_spec.rb` records pids before and after a `restart_on` edit and sees only that process's pid change, its siblings' unchanged, a `restarting` then `ready` status, and a fresh framing verdict when the preview process restarts.

Planner decisions (spec open questions 5, 10):

- **Mechanism:** polling, no new gem. Every second, snapshot `mtime` and size of the files matching each process's globs; a difference names the process.
- **Glob dialect:** Ruby `Dir.glob` relative to the checkout root, with `File::FNM_EXTGLOB` (`**/` recursive, `{a,b}` braces). Documented in YARD on `Watcher`.
- **Restart:** `Child` TERM, wait for exit (KILL after `TERM_GRACE`), spawn on the same port, wait ready.
- `Watcher.new(root:, definition:, clock:, sleeper:, interval: 1)`, `#changed -> Array<String>` (process names), `#run { |names| ... }`.

## B6 Wiring: CLI, Redis, the buttons, opt-in

- **Discipline:** back end
- **Covers spec items:** 10 (the server side of the buttons), 12 (engine exit), 13
- **Owns:**
  - `lib/openlanes/apps/runner.rb`: `Apps::Runner`, the foreground loop: start the supervisor, write its statuses through `Listing` every second (the heartbeat) and on each transition, poll the `Watcher`, read `app_commands`, stop on INT/TERM or a `stop` command
  - `lib/openlanes/cli/app/app.rb` and `subcommands/start.rb`, `status.rb`, `stop.rb`; `lib/openlanes/cli.rb` (register `app`)
  - `lib/openlanes/web/app.rb` (one route, `POST /api/apps/commands`)
  - specs: `spec/openlanes/apps/runner_spec.rb`, `spec/openlanes/cli/app_spec.rb`, `spec/openlanes/web/app_spec.rb` (the route only)
- **Must not touch:** `supervisor.rb`, `watcher.rb`, `lib/openlanes/live/commands.rb` (the engine's), `web/`
- **Depends on:** B4, B5
- **Done when:** `runner_spec.rb` drives a two-process fixture with an in-memory store: statuses appear in `Listing`, a `restart` command with `target: "backend"` restarts every non-preview process in declared order and `target: "<name>"` one, `stop` ends the loop with every port free and the plan's entry removed; `app_spec.rb` shows `openlanes app start` refusing a project without `app:` in one line with exit 65 and nothing written, `app status` printing the registry's rows for this machine, and `app stop NNN` sending TERM to the runner that owns the plan; `app_spec.rb` (web) answers 202 for a valid command, 422 for an unknown action or plan, 403 without the token; `bundle exec rspec` stays green.

Command shapes:

```
openlanes app start [NNN] [--redis-url URL] [--demo] [--ready-timeout 30]
openlanes app status            # every reserved port on this machine: plan, process, port, pid, root
openlanes app stop [NNN]        # TERM to the runner holding NNN's ports (every runner when omitted)

POST /api/apps/commands  (X-CSRF-Token)
  { "plan": "012.00", "action": "restart" | "stop", "target": "backend" | "<process name>" | null }
  202 { "plan", "action", "target" }   422 { "error" }   403 { "error" }
```

- `app start NNN` runs in the plan's worktree (`Vcs.worktree(root:).path_for(feature)`) when that directory exists, else the project root. The branch comes from `git rev-parse --abbrev-ref HEAD` there. Without NNN the plan is read off the branch name (`<user>/NNN.MM-slug`), else it is `000.00`.
- `--demo` writes under the `demo/<repo>` keys that `openlanes web --demo` reads, so the Cypress run can show a Preview tab beside the demo board.
- Redis is optional for `app start`: when it does not answer, the runner says so once and carries on with transitions on STDERR only. `app status` and `app stop` read the port registry and never need Redis.
- The engine itself does not start apps in this plan (decision 8), so `engine/` is untouched. `Execution::Child`'s `at_exit` group kill covers an exiting runner.
