<!-- generated-by: bin/wiki-gen -->

# Integrations

_Git, GitHub, Linear, the web control room, the apps a plan builds, and project setup._

**Up:** [Architecture](Architecture.md)

**In this section:** [OpenLanes::Vcs](OpenLanes-Vcs.md) · [OpenLanes::Linear](OpenLanes-Linear.md) · [OpenLanes::Web](OpenLanes-Web.md) · [OpenLanes::Apps](OpenLanes-Apps.md) · [OpenLanes::Setup](OpenLanes-Setup.md) · [OpenLanes::Skills](OpenLanes-Skills.md)

______________________________________________________________________

| Namespace                                  | Summary                                                                                                                                                                                                                                           |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`OpenLanes::Vcs`](OpenLanes-Vcs.md)       | Git and GitHub: a checkout per plan, pushing a branch, and reading pull requests.                                                                                                                                                                 |
| [`OpenLanes::Linear`](OpenLanes-Linear.md) | `.plans` as Linear projects and issues. The folders already are a tracker: a number, a state, a set of pull requests and a document saying why.                                                                                                   |
| [`OpenLanes::Web`](OpenLanes-Web.md)       | The control room's API server (plan 004, W3, W7): Sinatra on a threaded Puma, bound to 127.0.0.1.                                                                                                                                                 |
| [`OpenLanes::Apps`](OpenLanes-Apps.md)     | The app a plan builds, run on this machine (plan 012, M12, M13): the processes `.openlanes.yml` declares under `app:`, started in order on ports from 11100, kept ready, restarted when their files change, and shown in the control room's Prev… |
| [`OpenLanes::Setup`](OpenLanes-Setup.md)   | Gets a machine ready to run the factory (plan 035): the tools in the gem's `Brewfile`, then what brew cannot install.                                                                                                                             |
| [`OpenLanes::Skills`](OpenLanes-Skills.md) | The agent skills that ship inside the gem, under `skills/`, and the copy that puts them where a coding agent looks for them.                                                                                                                      |
