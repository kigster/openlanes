<!-- generated-by: bin/wiki-gen -->

# Agents and Execution

_Agent definitions, the CLI adapters they run through, and one agent invocation from spawn to after-check._

**Up:** [Architecture](Architecture.md)

**In this section:** [OpenLanes::Agents](OpenLanes-Agents.md) · [OpenLanes::Adapters](OpenLanes-Adapters.md) · [OpenLanes::Execution](OpenLanes-Execution.md) · [OpenLanes::Spawner](OpenLanes-Spawner.md) · [OpenLanes::Supervision](OpenLanes-Supervision.md) · [OpenLanes::Arbitration](OpenLanes-Arbitration.md) · [OpenLanes::Clock](OpenLanes-Clock.md)

______________________________________________________________________

| Namespace                                            | Summary                                                                                                                                                                                                                                           |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`OpenLanes::Agents`](OpenLanes-Agents.md)           | The specialists: their definitions in `agents/*.md`, the registry that loads and filters them, and the roster that reports on them.                                                                                                               |
| [`OpenLanes::Adapters`](OpenLanes-Adapters.md)       | The coding agents a plan can be handed to: `claude`, `codex`, `pi`, `grok` and `gemini`.                                                                                                                                                          |
| [`OpenLanes::Execution`](OpenLanes-Execution.md)     | One agent invocation: the child process, its clock, the control file it polls, and the transcript it streams back.                                                                                                                                |
| [`OpenLanes::Spawner`](OpenLanes-Spawner.md)         | The one place a child process is started, so a spec can start none.                                                                                                                                                                               |
| [`OpenLanes::Supervision`](OpenLanes-Supervision.md) | The factory's processes (S1–S5 in docs/decisions/decisions-on-factory-start-stop.md): a supervisor that keeps the engine and the web up, the PID file and title each process gives itself, and the checks every reader makes before it trusts or… |
| [`OpenLanes::Arbitration`](OpenLanes-Arbitration.md) | `arbitrator` (M7, M8, M9): a read-only agent that rules on the rejection cap, appeals, backend-coder-versus-frontend-coder disputes and `review-passed` verdicts at `mvp`.                                                                        |
| [`OpenLanes::Clock`](OpenLanes-Clock.md)             | A time source, so a spec can move time instead of waiting for it.                                                                                                                                                                                 |
