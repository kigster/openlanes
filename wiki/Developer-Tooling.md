<!-- generated-by: bin/wiki-gen -->

# Developer Tooling

_The command line, terminal UI, generated documents and diagrams, evals and coverage._

**Up:** [Architecture](Architecture.md)

**In this section:** [OpenLanes::CLI](OpenLanes-CLI.md) · [OpenLanes::UI](OpenLanes-UI.md) · [OpenLanes::Presentation](OpenLanes-Presentation.md) · [OpenLanes::Uml](OpenLanes-Uml.md) · [OpenLanes::Evals](OpenLanes-Evals.md) · [OpenLanes::Coverage](OpenLanes-Coverage.md)

______________________________________________________________________

| Namespace                                              | Summary                                                                                                                                                                                                                                       |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`OpenLanes::CLI`](OpenLanes-CLI.md)                   | The command line. Every command is a thin shell over one library class: it parses flags, calls one object, and prints the result.                                                                                                             |
| [`OpenLanes::UI`](OpenLanes-UI.md)                     | Everything the user sees that is not the deliverable itself.                                                                                                                                                                                  |
| [`OpenLanes::Presentation`](OpenLanes-Presentation.md) | Everything a person reads: the live dashboard, the status table, the generated conventions and the state diagram.                                                                                                                             |
| [`OpenLanes::Uml`](OpenLanes-Uml.md)                   | Class diagrams drawn from Ruby source read statically with Prism: the project being built, or OpenLanes itself.                                                                                                                               |
| [`OpenLanes::Evals`](OpenLanes-Evals.md)               | Per-agent evals: did the agent finish the task, and did it work at the depth it was asked for? A case (`evals/cases/<agent>/<id>.yml`) describes a fixture plan, the depth requested and the deterministic checks that hold an agent to both. |
| [`OpenLanes::Coverage`](OpenLanes-Coverage.md)         | A project's declared test coverage (decision M15), the `coverage:` section of its `.openlanes.yml`: which command runs the suite, where the line figure comes from, and the lowest one that may merge.                                        |
