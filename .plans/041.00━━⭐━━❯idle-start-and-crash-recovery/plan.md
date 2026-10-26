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

- [ ] `libexec/openlanes-agent` and its spec, run as a real process.
- [ ] `Execution::AgentProcess`: spawns it, tails the output, reads the status, and answers `Child`'s interface (`pid`, `each_chunk`, `wait`, `terminate`, `kill`, `alive?`, `finished?`).
- [ ] `Executor` spawns through `AgentProcess`.
- [ ] `Supervision`: an `AGENT` role in the PID dir's order, `status` rows, and `stop --all`.
- [ ] Docs: decisions S6 (as built), `docs/USAGE.md`, the architecture docs.
- [ ] Lint, the full suite, and every changed file above 95% coverage.

## PR 2: reattach

To be planned once PR 1 is merged.

## PR 3: graceful shutdown (S7)

To be planned once PR 2 is merged.
