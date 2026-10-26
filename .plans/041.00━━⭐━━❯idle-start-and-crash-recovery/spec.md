---
created: 2026-10-20
starts: research
depends_on: ["039.00"]
---

# Idle Start and Crash Recovery

Source: GitHub issue #95, https://github.com/kigster/openlanes/issues/95. Rescoped on 2026-10-26 to carry S6 and S7 from [decisions-on-factory-start-stop.md](../../docs/decisions/decisions-on-factory-start-stop.md), which overlapped it.

## What we are trying to achieve

An agent outlives its engine. A small `openlanes-agent` process per agent owns the agent CLI and writes its output and exit status to files (S6). A restarted engine finds the agents still running and reattaches to them; it resumes the ones that died. Shutdown gives every agent the grace to leave a resume note (S7).

Delivered as three pull requests, one at a time:

1. **The agent supervisor.** `libexec/openlanes-agent`, plain Ruby with the standard library only, starts the CLI, appends its output to a file, writes its exit status beside it, and writes `tmp/pids/agent-<plan>-<agent>.pid`. The engine starts agents through it and reads the file instead of a pipe. Behaviour is otherwise unchanged: an engine that exits still stops its agents.
1. **Reattach.** A restarted engine reads the agent PID files and the event journal, reattaches to each live agent from its journaled offset, and resumes each dead one with `--resume` or a fresh round. An engine stopped for a restart leaves its agents running. Nothing runs twice.
1. **Graceful shutdown (S7).** TERM to the supervisor stops dispatching, sends USR1 to every agent supervisor (which writes `INTERRUPT` to its control file), waits out the grace, then TERMs what is left. `$OPENLANES_SHUTDOWN_GRACE` overrides the 60 seconds.

Idle start (`openlanes start` waiting for Start All) stays in this spec but is not in the three pull requests above.

## Why it matters

A crash, a kill or a restart of the engine never loses an agent's work in flight, and a stop gives each agent the time to write down where it got to.

## What already exists

- `Execution::Child`: a pipe plus a process group per agent.
- `Execution::Control`: control files, INTERRUPT, the 60-second grace.
- `Engine::EventJournal` and `Replay`: each running agent's pid, session, output file and offset.
- `Supervision`: PID files, `Probe` (pid + `lstart` + title), the supervisor, `stop`, `status` (#144).

## How to tell it's working?

- An agent started by the engine shows in `ps` as `openlanes-agent [<project>] <plan> <agent>`, and its PID file in `openlanes status`.
- `kill -9` of the engine, then a restart: surviving agents are reattached, dead ones are resumed, and nothing runs twice.
- A reused PID is not mistaken for an agent.
- `openlanes stop` gives running agents the grace to leave a resume note before anything is killed.
