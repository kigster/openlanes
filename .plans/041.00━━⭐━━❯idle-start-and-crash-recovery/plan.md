# Plan: Idle Start and Crash Recovery

Three pull requests, in order. Each lands on `main` before the next starts.

## PR 1: the agent supervisor

### Decisions

- **A1. One script, no gem.** `libexec/openlanes-agent` runs as `ruby --disable-gems`, so it loads neither Bundler, Zeitwerk nor the gem. It speaks a protocol: argv in; an output file, a status file and a PID file out; signals in. Nothing else couples it to the engine.
- **A2. Argv.** `openlanes-agent --root R --plan P --agent A --output O --status S -- <cli argv>`. The environment it is started with is the CLI's environment, passed through unchanged.
- **A3. Output.** The CLI's stdout and stderr are appended to `<trace dir>/agent-<plan>-<agent>-<pid>.out`, raw. The engine tails that file and feeds its `Transcript`, which goes on writing the filtered trace as before. The engine removes the `.out` and `.status` files once it has read both to the end.
- **A4. Status.** When the CLI ends, the agent supervisor writes `{"exitstatus": N}` or `{"termsig": N}` to the status file (tmp file plus rename), removes its PID file, and exits with the CLI's status.
- **A5. PID file.** `tmp/pids/agent-<plan>-<agent>.pid`, in the same JSON as every other PID file (`role: "agent"`, `pid`, `started` from `ps -o lstart=`, `root`), plus `plans: [<plan>]` and `agent`. Its title is `openlanes-agent [<project>] <plan> <agent>`, so `Probe` verifies it like any other process.
- **A6. Groups.** The engine starts the agent supervisor in a process group of its own, so a terminal's Ctrl-C reaches neither. The agent supervisor starts the CLI in another group of its own, so TERM and KILL reach every tool the CLI started.
- **A7. Signals.** TERM to the agent supervisor: TERM to the CLI's group, KILL after `Child::TERM_GRACE`, then the status file. USR1 is PR 3.
- **A8. An engine that exits still stops its agents (until PR 2).** Its `at_exit` TERMs every agent supervisor it started, and each one finishes the stop by itself, so the engine does not wait.
- **A9. `stop` and `status`.** `status` lists agents. A plain `stop` leaves them to their engine or run; `stop --all` stops whatever is left.
- **A10. Only the executor moves.** `Child` stays for the preview apps, the coverage gate and the copilot.

### Work units

- [x] `libexec/openlanes-agent` and its spec, run as a real process.
- [x] `Execution::AgentProcess`: spawns it, tails the output, reads the status, and answers `Child`'s interface (`pid`, `each_chunk`, `wait`, `terminate`, `kill`, `alive?`, `finished?`).
- [x] `Executor` spawns through `AgentProcess`.
- [x] `Supervision`: an `AGENT` role in the PID dir's order, `status` rows, and `stop --all`.
- [x] Docs: decisions S6 (as built), `docs/USAGE.md`, the architecture docs.
- [x] Lint, the full suite, and every changed file above 95% coverage.
- [x] The engine's state file names the session of an agent that ends before the first poll.
- [x] `engine_command_spec` stops the engine with INT, as the supervisor does; a real TERM now ends the process.

## PR 2: reattach

### Decisions

Settled with the user on 2026-10-27: B1 to B4. The rest follow from them.

- **B1. Full reattach.** A restarted engine adopts a live agent as a running job: board row, timeout, controls, transcript. When it ends it is settled like any other run: boundary check, rename, publish. No round is spent and no stage is written twice.
- **B2. Which exits leave agents running.** A deliberate quit (`q`, Stop All, Ctrl-C, INT) stops them, as today. A crash, a TERM or `kill -9` leaves them for the next engine. The engine no longer traps TERM; its `at_exit` TERMs its agents only when `Control.quit?`. A TERMed engine ends on a signal, which the supervisor counts as a crash and restarts.
- **B3. TERM to the supervisor stops the whole system.** `Shutdown` sends INT to the engine and the web, so the engine quits deliberately and writes its interrupted records, waits out the grace, then TERMs every agent supervisor of its project still alive, then KILLs what is left. `openlanes stop` with no supervisor sends INT, not TERM, to an engine or a run, for the same reason. S7's USR1 grace is PR 3.
- **B4. The timeout stays in the engine.** Each agent's deadline is kept as wall-clock time, moved by every extension. A reattaching engine starts the clock with what is left; an overdue agent is stopped at once. An orphan runs until it ends, `stop --all`, or the next engine.
- **B5. The restart context lives in the state file.** `Engine::StateFile` is already the restart record `Recovery::Stranded` reads, so each Started stage also keeps what reattach needs: the agent supervisor's pid and files, the control file, the trace, the checkout, the boundary snapshot taken before the run, the deadline and the session. The event journal stays the record of what happened; no journaled offset is needed (B7).
- **B6. Live, finished while away, or dead.** A stage is reattached when its PID file is verified by `Probe` and names the same pid, or when its status file is there (the agent ended while no engine ran). Otherwise it is stranded, and `Recovery::Stranded` resumes it as today. A live agent supervisor with no stage to explain it is left alone: another engine or a `run` may own it. It shows in `status` and `stop --all` stops it.
- **B7. The transcript is rebuilt from byte 0.** The output file holds everything the CLI wrote, so the filtered trace is truncated and rewritten whole, and token counts come out right.
- **B8. Same path as a start.** The reattached job runs through the dispatcher's own job thread, plan lock and settle; `Executor#reattach` is `#call` from the drain onwards. `Recovery::Stranded` skips every stage that was reattached.
- **B9. Verifier agents are not reattached.** Their preview app ran under the dead engine. They are TERMed and resumed by `Recovery::Stranded`.

### Work units

- [x] `AgentProcess.attach` from a recorded stage, and `Executor#reattach`.
- [x] Restart context in the state file, written at start and on every extension.
- [x] `Recovery::Reattach`: find live and finished agents, hand them to the dispatcher before `Stranded` runs.
- [x] Dispatcher: start a job from a reattached agent.
- [x] Exits (B2): no TERM trap in the engine, `at_exit` only on a deliberate quit.
- [x] Supervisor and `stop` (B3): INT to engines and runs, then TERM to leftover agents.
- [x] Docs: decisions S6/S7 table, `docs/USAGE.md`, architecture.
- [x] Lint, the full suite, and every changed file above 95% coverage.
- [x] The engine's state file names the session of an agent that ends before the first poll.
- [x] `engine_command_spec` stops the engine with INT, as the supervisor does; a real TERM now ends the process.

## PR 3: graceful shutdown (S7)

### Decisions

Settled with the user on 2026-10-27: C1 and C2. The rest follow from them.

- **C1. A system stop is a pause.** Every running agent is told `INTERRUPT`: leave a resume note, and the next start resumes the session. This is what INT to the engine already broadcasts (`Control#interrupt!`), with `Control::GRACE` before the executor kills what is left.
- **C2. Every agent is told at once.** On TERM the supervisor sends USR1 to every verified agent supervisor of its project, alongside INT to the engine and the web, so an agent whose engine is dead or hung is told too. Each agent supervisor writes `INTERRUPT` into its agent's control file, which it now receives as `--control`. One shared grace is waited out; then the sweep TERMs what is left, and KILLs the CLI's group of one that outlives its stop.
- **C3. One override.** `$OPENLANES_SHUTDOWN_GRACE` (seconds) sets `Control::GRACE` and the supervisor's wait alike, as S7 says. A bad value is refused with a warning and the default used.
- **C4. A second TERM, or `openlanes stop` twice, skips the grace**, as it already does for the children: USR1 has been sent, so the sweep TERMs at once.
- **C5. `openlanes stop --all` with no supervisor** does the same for the agents it finds: USR1, the agents' grace, then TERM.

### Work units

- [ ] Agent supervisor: `--control PATH`, USR1 writes `INTERRUPT` there; the executor passes the file.
- [ ] Supervisor: USR1 to every agent up front; the sweep after one shared grace.
- [ ] `stop --all`: USR1 to agents first.
- [ ] `$OPENLANES_SHUTDOWN_GRACE` for `Control::GRACE` and the supervisor.
- [ ] Docs: S7 table and notes, `docs/USAGE.md`, architecture.
- [ ] Lint, the full suite, and every changed file above 95% coverage.
