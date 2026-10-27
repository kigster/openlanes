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
| `openlanes start --background` | The same, detached from the terminal (one spawn, `setsid` in the child, parent PID 1 once `start` returns) |
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

### C6. `run --until <state>` ends a run early, for dogfooding

`openlanes run 050 --until <state>` ends as soon as every listed plan has reached that state (a status key or its emoji), or has passed it on its lane. Together with `starts:` in `spec.md` it runs one slice of the pipeline at a time, so openlanes can be tried on its own plans in short bursts:

| `starts:`  | `--until`          | Exercises                                     |
| :--------- | :----------------- | :-------------------------------------------- |
| `planning` | `building`         | the planner                                   |
| `building` | `ready-for-review` | the builders                                  |
| `building` | (none)             | building, review and verification, to the end |

- Where a plan starts stays in `starts:`, and in the folder's name for a folder made by hand. There is no `--from`: it would say a second time what `starts:` says, and the two could disagree.
- A run that reaches review opens a real pull request on this repository. That is wanted: the pull request is reviewed like any other, by a person or by the session that started the run, and merged or closed on its merits. `--no-git-push` keeps one local.

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
- `start` refuses while a supervisor's PID file names a live process that is that supervisor (S2), and prints that factory's URL. A PID file whose number now belongs to some other process is stale: `start` removes it and goes on.

The engine and web restarting each other was considered and rejected: `stop` becomes a race, a slow restart seen from both sides can start two pairs, and the web would have to learn how to start an engine.

### S2. Every process writes its own PID file and removes it on a clean exit

`supervisor.pid`, `engine.pid`, `web.pid`, and `run-<pid>.pid` for each `run`, which also records that run's plans. A PID file whose process is gone means a crash: `status` reports it, and the supervisor restarts the child.

A PID alone is not proof: the operating system reuses numbers, and a PID file left by a crash can name an unrelated process by the time anyone reads it. So a PID file records the PID, the process's start time and the project root, and a process counts as the one the file names only when all three match: its start time (`ps -o lstart=`) equals the recorded one, and its title (S5) names the expected role and project. Every reader checks this, `start`, `stop`, `status` and the supervisor alike, and a file that fails it is a crash, never a target. `stop` signals nothing it has not checked this way.

`stop` sends a signal, waits, sends it again, waits briefly, then KILL. The signal is INT for an engine or a run, the deliberate quit that stops their agents (TERM would leave them, S7), and TERM for a web, a supervisor or an agent supervisor. The first wait is about ten seconds for a web, the supervisor's own grace plus ten for a supervisor, the agents' grace (S7) plus ten for an engine or a run, and an agent supervisor's own stop for an agent. The second INT is the engine's second Ctrl-C: it KILLs its agents' process groups and exits, which a KILL to the engine would never do. The supervisor stops its children the same way, then TERMs every agent supervisor of its project still alive. It also stops a lone engine or web whose supervisor is already gone.

Two processes of one role cannot both register: each takes an exclusive `flock` on `<role>.lock` beside its PID file before it reads or writes one, and holds it until it exits. The kernel drops the lock when the process dies, so a crash never leaves it held.

### S3. PID files live in `tmp/pids/` at the project root

- `<project root>/tmp/pids/`, so each project has its own and two projects can each run a factory. `.gitignore` already ignores `/tmp/`.
- `$OPENLANES_PID_DIR` is the only override. A flag or a config key is easy to give one process and forget for another, and every process has to agree on the directory.

### S4. Background output goes to `log/`

`--background` sends what would have gone to the terminal to `log/openlanes-start.log`.

### S5. Every process names itself

Each process sets its title (`Process.setproctitle`; Puma through its `tag` option), lower case and hyphenated, with live status in brackets the way Sidekiq does:

```
openlanes-supervisor [myproj] up 2h, 1 restart
├── openlanes-engine [myproj] 3 of 8 agents busy
│   └── openlanes-agent [myproj] 005.00 backend-coder          (S6)
└── puma 8.0.2 (tcp://127.0.0.1:11000) [openlanes-web myproj]
openlanes-run [myproj] 005,006
```

`pgrep -f openlanes-` finds every one, and the project name tells two factories apart. On macOS, `ps aux` and `pgrep -f` show the title; Activity Monitor and `ps -c` still say `ruby`.

### S6. An agent supervisor between the engine and each agent

Built as plan 041 in three pull requests: the agent supervisor (PR 1, below), a restarted engine reattaching to it (PR 2), and S7 (PR 3).

Today the engine spawns each agent CLI as its own child (`Execution::Child`) and reads it through a pipe, so an engine that dies or is restarted takes every running agent with it. A small `openlanes-agent` process per agent owns the CLI instead, so an agent outlives a restart of the engine:

- It writes the transcript to a file in the trace directory and, when the agent ends, its exit status beside it. The engine follows the file. A pipe to the engine (`popen3`) was rejected: the engine's death would close it and end the run.
- It writes `tmp/pids/agent-<plan>-<agent>.pid`. A restarted engine finds those files and reattaches to the runs still going.
- Stops reach it as signals (S7). The timeout clock, the controls and the transcript reader move from the pipe to the file.
- It is lean Ruby: the standard library only, no Bundler, no Zeitwerk, nothing from the gem, about 15 MB and 50 ms to start.
- As built in PR 1:
  - The script is `libexec/openlanes-agent`, run as `ruby --disable-gems`; it loads `execution/agent_supervisor.rb` alone. The engine's side is `Execution::AgentProcess`, which answers `Child`'s interface, so the executor, the clock and the controls read an agent as before.
  - argv: `--root --plan --agent --output --status --pid-file -- <cli argv>`. The engine names the PID file, so `$OPENLANES_PID_DIR` is resolved in one place and the agent supervisor, started with the unbundled environment, needs no copy of it.
  - The output (stdout and stderr together) is `agent-<plan>-<agent>-<pid>-<hex>.out` in the trace directory, the status `.status` beside it (`{"exitstatus": 3}` or `{"termsig": 9}`), both written atomically and removed once the engine has read them.
  - The PID file is the same JSON as every other one, with `role: "agent"`, the plan, the agent, and the CLI's pid as `child`. Its title, `openlanes-agent [<project>] 005.00 backend-coder`, starts with the project, so `Probe` verifies it like the others.
  - `openlanes status` lists agents; `openlanes stop` leaves them to their engine, and `stop --all` stops them too.
  - Until reattach (PR 2), an engine that exits still stops its agents: its `at_exit` TERMs every agent supervisor, and each finishes the stop by itself. An agent supervisor that outlives its own grace by 5 s is KILLed from the engine, with the CLI's group.
- As built in PR 2 (plan 041, B1 to B9):
  - Each Started stage in the engine's state file keeps a `restart` context: the agent supervisor's pid and files, the checkout, the trace, the control file, the boundary snapshot taken before the run, and the deadline as wall-clock time, moved by every extension.
  - A starting engine looks for the stages a dead run left: one whose agent supervisor is still running (its PID file names the recorded pid and `Probe` verifies it), or ended with its status written, is taken back as a running job: board row, clock, controls, a transcript rebuilt from the start of the output, and the usual settle. The rest are stranded, as before. A verifier is stopped instead, since its preview app died with the engine.
  - An engine's `at_exit` stops its agents only after a deliberate quit (`Control.quit?`); a crash, a TERM or `kill -9` leaves them for the next one. Anything else that runs agents, without a state file to find them again, still stops them whenever it exits.
  - A live agent supervisor no stage explains is left alone: another engine or a `run` may own it. `status` lists it and `stop --all` stops it.
- The engine knows it only through its protocol (argv in; transcript, exit status and PID files out; signals for control), so a native build can replace it without the engine noticing. Should one ever be needed, C compiled at install through the gem's `ext/` is preferred over Rust: it needs no prebuilt binaries per platform and no cargo. Neither is worth it today. The saving is about 14 MB per agent, beside an agent CLI's 200 to 400 MB, and the cost is fork, exec and signal code in a language this repository does not otherwise use.

### S7. Shutdown gives agents 60 seconds to wrap up

| Signal, to                | Means                                                                                                      |
| :------------------------ | :--------------------------------------------------------------------------------------------------------- |
| TERM, to the supervisor   | Stop the whole system: INT to the engine and the web, so the engine quits deliberately and stops its agents; then TERM to any agent supervisor of the project still alive. Graceful shutdown (USR1 and the grace first) is plan 041, PR 3 |
| USR1, to an agent supervisor | Write `INTERRUPT` into its agent's control file                                                         |
| TERM, to an agent supervisor | Stop now: TERM to the agent's process group, KILL after `Child::TERM_GRACE`                             |
| TERM, to the engine       | Exit at once and leave the agents running; the supervisor counts it a crash, restarts it, and it reattaches (S6) |
| INT, to the engine        | Quit deliberately: stop dispatching and stop the agents, as Ctrl-C does                                     |
| A second TERM, or Ctrl-C twice | Skip the grace and stop everything now                                                                |

- The grace is 60 seconds, the same as `Execution::Control::GRACE`. `$OPENLANES_SHUTDOWN_GRACE` is its only override, as with S3. Agents that finish sooner end the wait sooner.
- An agent is told through its control file (`execution/control.rb`), not a signal and not stream-json. The model never sees a signal: the CLI receives it, and SIGUSR1's default action is to terminate. The control file is named in every agent's prompt and read at each step, so it works for claude, codex, pi, grok and gemini alike, and `INTERRUPT` already means "the run will be started again: leave a resume note".
- Little is lost even at the deadline: the CLI keeps the session on disk as it goes (M1 in [decisions-on-agent-memory-and-sessions.md](decisions-on-agent-memory-and-sessions.md)), the journal reaches `state.json` line by line (M2), and the files stay in the plan's worktree. The next start resumes each interrupted session with its journal.

## Not adopted

### X1. Sidekiq

Sidekiq was considered and rejected:

- It is itself a process that needs supervising, so it does not solve S1.
- Its shutdown waits 25 seconds and then reruns an unfinished job from scratch, and an agent rerun costs tokens and rewrites files.
- The dispatcher's scheduling (dependencies, one plan per group, pairs started together, the fixed point) does not fit a queue; it would be decided twice.
- Starting a pair together needs Batches, which is in the commercial Pro tier. Sidekiq itself is LGPLv3.

Reconsider it if agent runs ever move off the machine that runs the engine.
