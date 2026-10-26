# Decisions on starting, stopping and supervising the factory

Started 2026-10-25 by the owner (kig), grilling session, one question at a time.

## Status

Settled 2026-10-25. Not built yet.

## Why

`openlanes start` and `openlanes run` overlapped almost completely: a bare `run` served the control room and stayed up when Redis answered, and ended like a batch job when it did not, so the command line never said which one you would get. `--no-web --stay` and `--until-settled` existed to patch the gap.

Separately, the web server outlived the engine more than once. `Web::Launcher` starts it in a process group of its own, on purpose, and only the engine's own `stop` ends it, so an engine that is SIGKILLed or crashes leaves the web up with nothing behind it.

## Commands

### C1. `start`, `stop` and `status` belong to the factory

| Command                      | Does                                                                                     |
| :--------------------------- | :--------------------------------------------------------------------------------------- |
| `openlanes start`            | The factory: the supervisor, the engine and the web, until `stop`, Stop All Local or Ctrl-C |
| `openlanes start --background` | The same, detached from the terminal (double fork, `setsid`, parent PID 1)             |
| `openlanes stop`             | Stops the factory                                                                        |
| `openlanes stop --all`       | Stops the factory and every `openlanes run`                                              |
| `openlanes status`           | Which processes are up, with PIDs, ports, URL and uptime, any crashed one, every `run`, and plan counts by state |

### C2. `app` becomes `project`, alias `preview`

`openlanes project start|stop|status` (alias `openlanes preview`) runs the project being built, from the start command in `.openlanes.yml` `app:`. There is no `app` command any more. Booting that app stays out of the factory, except where the verifier already needs it running (`engine/verification/app_session.rb`).

### C3. The plan table is `openlanes plans`

`list-plans` and `st` are removed, with no aliases. Nothing outside this repository uses openlanes, so nothing needs to keep working under the old names.

### C4. `run` is headless and takes plans

- `openlanes run 005,006` requires one or more plan ids, comma separated, and works only those, in an engine of its own, beside the factory or without it.
- It never serves the control room and always ends at the fixed point. `--web`, `--open`, `--port`, the listen and admin-credential flags, `--stay` and `--until-settled` are removed.
- `-n`, `-j` and the per-agent flags stay.

### C5. `web` is internal

`openlanes web` stays only as the hidden entry point the supervisor spawns. Running it on its own is how a page came to outlive its engine.

## Overlaps

### O1. `run` claims every listed plan before any agent starts

An engine claims a plan today only when it starts an agent on it, so a plan the factory is holding but not yet working (waiting, queued, blocked) is held by nobody. `run` claims all of its plans up front and holds them until it exits:

- The claim is the check: Redis `SET NX` (`live/claims.rb`) is atomic, so nothing can take a plan between the check and the claim. Without Redis, `locked-by.pid` and the plan's alock do the same on one machine.
- The factory steps around a plan a `run` holds, as it already does for a plan claimed elsewhere, and the board shows who holds it.
- A clean exit releases the plans. A crashed `run` lets them lapse after the claim TTL.

### O2. Any held plan rejects the whole command

If any listed plan is already held, `run` claims nothing, releases what it took, exits non-zero, and names each holder and when it took the plan. The plans were asked for together.

## Supervision

### S1. A thin supervisor owns the engine and the web

`openlanes start` becomes a supervisor that spawns the engine and the web as its children and does nothing else:

- It restarts whichever child dies, with backoff. After about three crashes in five minutes it stops restarting that child, keeps the rest up, and reports the failure on the page and in `status`.
- `stop` signals the supervisor, which stops both children. Nothing is left that could restart them.
- Each child watches a pipe from the supervisor and exits when it closes, so a SIGKILLed supervisor never leaves a web without its engine.
- `start` refuses while a live supervisor's PID file exists, and prints that factory's URL.

The engine and web restarting each other was considered and rejected: `stop` becomes a race, a slow restart seen from both sides can start two pairs, and the web would have to learn how to start an engine.

### S2. Every process writes its own PID file and removes it on a clean exit

`supervisor.pid`, `engine.pid`, `web.pid`, and `run-<pid>.pid` for each `run`, which also records that run's plans. A PID file whose process is gone means a crash: `status` reports it, and the supervisor restarts the child.

`stop` sends TERM, waits about ten seconds, then KILL. It also stops a lone engine or web whose supervisor is already gone.

### S3. PID files live in `tmp/pids/` at the project root

- `<project root>/tmp/pids/`, so each project has its own and two projects can each run a factory. `.gitignore` already ignores `/tmp/`.
- `$OPENLANES_PID_DIR` is the only override. A flag or a config key is easy to give one process and forget for another, and every process has to agree on the directory.

### S4. Background output goes to `log/`

`--background` sends what would have gone to the terminal to `log/openlanes-start.log`.

## Not adopted

### X1. Sidekiq

Sidekiq was considered and rejected:

- It is itself a process that needs supervising, so it does not solve S1.
- Its shutdown waits 25 seconds and then reruns an unfinished job from scratch, and an agent rerun costs tokens and rewrites files.
- The dispatcher's scheduling (dependencies, one plan per group, pairs started together, the fixed point) does not fit a queue; it would be decided twice.
- Starting a pair together needs Batches, which is in the commercial Pro tier. Sidekiq itself is LGPLv3.

Reconsider it if agent runs ever move off the machine that runs the engine.
