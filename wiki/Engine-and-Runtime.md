<!-- generated-by: bin/wiki-gen -->

# Engine and Runtime

_The round loop, the dispatcher, and the state, events and logs a run leaves behind._

**Up:** [Architecture](Architecture.md)

**In this section:** [OpenLanes::Engine](OpenLanes-Engine.md) · [OpenLanes::Events](OpenLanes-Events.md) · [OpenLanes::Live](OpenLanes-Live.md) · [OpenLanes::Log](OpenLanes-Log.md) · [OpenLanes::Container](OpenLanes-Container.md)

______________________________________________________________________

| Namespace                                        | Summary                                                                                                                                                                                                                   |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`OpenLanes::Engine`](OpenLanes-Engine.md)       | The run loop: which agent works which plan, in what order, until a round changes nothing.                                                                                                                                 |
| [`OpenLanes::Events`](OpenLanes-Events.md)       | The durable record of runs (plan 020.01): an opt-in, append-only JSONL log of run, agent, block/answer and PR events, kept outside the repo and outside Redis, and the aggregates read back from it.                      |
| [`OpenLanes::Live`](OpenLanes-Live.md)           | The live run in Redis (plan 004): the engine publishes its board there and reads the page's commands from there, and machines sharing one Redis see each other's boards and never take each other's plans (W6, W13, W26). |
| [`OpenLanes::Log`](OpenLanes-Log.md)             | The one place a process sets SemanticLogger up, so the engine and the control room's server write the same file the same way.                                                                                             |
| [`OpenLanes::Container`](OpenLanes-Container.md) | The application's components, and the outside world they reach (A1).                                                                                                                                                      |
