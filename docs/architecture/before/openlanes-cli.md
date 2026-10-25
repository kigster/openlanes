<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::CLI

```mermaid
classDiagram
  class OpenLanes__Apps__Supervisor["OpenLanes::Apps::Supervisor"]
  class OpenLanes__Apps__Supervisor__StartFailed["OpenLanes::Apps::Supervisor::StartFailed"]
  class OpenLanes__CLI__API__Docs["API::Docs"]
  class OpenLanes__CLI__Agents__Describe["Agents::Describe"]
  class OpenLanes__CLI__Agents__List["Agents::List"]
  class OpenLanes__CLI__App__Registry["App::Registry"]
  <<module>> OpenLanes__CLI__App__Registry
  class OpenLanes__CLI__App__Start["App::Start"]
  class OpenLanes__CLI__App__Status["App::Status"]
  class OpenLanes__CLI__App__Stop["App::Stop"]
  class OpenLanes__CLI__Base["Base"]
  class OpenLanes__CLI__Coverage["Coverage"]
  class OpenLanes__CLI__Create["Create"]
  class OpenLanes__CLI__Docs["Docs"]
  class OpenLanes__CLI__Eval["Eval"]
  class OpenLanes__CLI__Events__Report["Events::Report"]
  class OpenLanes__CLI__Index["Index"]
  class OpenLanes__CLI__Init["Init"]
  class OpenLanes__CLI__Linear__Import["Linear::Import"]
  class OpenLanes__CLI__Linear__Projects["Linear::Projects"]
  class OpenLanes__CLI__Linear__Team["Linear::Team"]
  class OpenLanes__CLI__Link["Link"]
  class OpenLanes__CLI__ListPlans["ListPlans"]
  class OpenLanes__CLI__Mail__Ack["Mail::Ack"]
  class OpenLanes__CLI__Mail__Locating["Mail::Locating"]
  <<module>> OpenLanes__CLI__Mail__Locating
  class OpenLanes__CLI__Mail__Read["Mail::Read"]
  class OpenLanes__CLI__Mail__Render["Mail::Render"]
  class OpenLanes__CLI__Mail__Send["Mail::Send"]
  class OpenLanes__CLI__Resync__Dirs["Resync::Dirs"]
  class OpenLanes__CLI__Resync__Prs["Resync::Prs"]
  class OpenLanes__CLI__Review["Review"]
  class OpenLanes__CLI__Run["Run"]
  class OpenLanes__CLI__Setup["Setup"]
  class OpenLanes__CLI__Skills__Install["Skills::Install"]
  class OpenLanes__CLI__Start["Start"]
  class OpenLanes__CLI__State__Locating["State::Locating"]
  <<module>> OpenLanes__CLI__State__Locating
  class OpenLanes__CLI__State__Resume["State::Resume"]
  class OpenLanes__CLI__State__Show["State::Show"]
  class OpenLanes__CLI__State__Sign["State::Sign"]
  class OpenLanes__CLI__States["States"]
  class OpenLanes__CLI__Unblock["Unblock"]
  class OpenLanes__CLI__Version["Version"]
  class OpenLanes__CLI__Web["Web"]
  class OpenLanes__CLI__Worktree["Worktree"]
  class OpenLanes__CLI__WorktreePrune["WorktreePrune"]
  class OpenLanes__Config["OpenLanes::Config"]
  class OpenLanes__Coverage__Config["OpenLanes::Coverage::Config"]
  class OpenLanes__Coverage__Invalid["OpenLanes::Coverage::Invalid"]
  class OpenLanes__Engine__Dispatcher["OpenLanes::Engine::Dispatcher"]
  class OpenLanes__Engine__RunWorkflow["OpenLanes::Engine::RunWorkflow"]
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Evals__Invalid["OpenLanes::Evals::Invalid"]
  class OpenLanes__Evals__Live["OpenLanes::Evals::Live"]
  class OpenLanes__Evals__Run["OpenLanes::Evals::Run"]
  class OpenLanes__Lifecycle__UnblockWorkflow["OpenLanes::Lifecycle::UnblockWorkflow"]
  class OpenLanes__Linear__API["OpenLanes::Linear::API"]
  class OpenLanes__Linear__Import["OpenLanes::Linear::Import"]
  class OpenLanes__Linear__Survey["OpenLanes::Linear::Survey"]
  class OpenLanes__Live__Copilot__Operator["OpenLanes::Live::Copilot::Operator"]
  class OpenLanes__Live__Mail["OpenLanes::Live::Mail"]
  class OpenLanes__Live__Node["OpenLanes::Live::Node"]
  class OpenLanes__Live__Node__Invalid["OpenLanes::Live::Node::Invalid"]
  class OpenLanes__Live__Unavailable["OpenLanes::Live::Unavailable"]
  class OpenLanes__Log__Invalid["OpenLanes::Log::Invalid"]
  class OpenLanes__Log__Settings["OpenLanes::Log::Settings"]
  class OpenLanes__Plans__Feature["OpenLanes::Plans::Feature"]
  class OpenLanes__Plans__LastKnownState["OpenLanes::Plans::LastKnownState"]
  class OpenLanes__Plans__Mailbox["OpenLanes::Plans::Mailbox"]
  class OpenLanes__Plans__Ordinal["OpenLanes::Plans::Ordinal"]
  class OpenLanes__Plans__PlanState["OpenLanes::Plans::PlanState"]
  class OpenLanes__Plans__ReviewLabel["OpenLanes::Plans::ReviewLabel"]
  class OpenLanes__Plans__Spec["OpenLanes::Plans::Spec"]
  class OpenLanes__Presentation__ApiDocs["OpenLanes::Presentation::ApiDocs"]
  class OpenLanes__Presentation__EventsReport["OpenLanes::Presentation::EventsReport"]
  class OpenLanes__Setup__CiScaffold["OpenLanes::Setup::CiScaffold"]
  class OpenLanes__Setup__Stack["OpenLanes::Setup::Stack"]
  class OpenLanes__Setup__StackDocument["OpenLanes::Setup::StackDocument"]
  class OpenLanes__UI["OpenLanes::UI"]
  <<module>> OpenLanes__UI
  class OpenLanes__Vcs__Worktree["OpenLanes::Vcs::Worktree"]
  class OpenLanes__Web__AdminAuth["OpenLanes::Web::AdminAuth"]
  class OpenLanes__Web__AdminAuth__Invalid["OpenLanes::Web::AdminAuth::Invalid"]
  class OpenLanes__Web__Demo["OpenLanes::Web::Demo"]
  class OpenLanes__Web__Launcher["OpenLanes::Web::Launcher"]
  class OpenLanes__Web__Listen["OpenLanes::Web::Listen"]
  class OpenLanes__Web__Listen__Invalid["OpenLanes::Web::Listen::Invalid"]
  class OpenLanes__Web__Stores["OpenLanes::Web::Stores"]
  OpenLanes__CLI__API__Docs --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__API__Docs ..> OpenLanes__Presentation__ApiDocs : uses
  OpenLanes__CLI__API__Docs ..> OpenLanes__UI : uses
  OpenLanes__CLI__Agents__Describe ..> OpenLanes__Error : uses
  OpenLanes__CLI__Agents__Describe ..|> OpenLanes__UI : includes
  OpenLanes__CLI__Agents__List ..|> OpenLanes__UI : includes
  OpenLanes__CLI__App__Registry ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__CLI__App__Start ..> OpenLanes__Apps__Supervisor : uses
  OpenLanes__CLI__App__Start ..> OpenLanes__Apps__Supervisor__StartFailed : uses
  OpenLanes__CLI__App__Start ..|> OpenLanes__CLI__App__Registry : includes
  OpenLanes__CLI__App__Start --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__App__Start ..> OpenLanes__Config : uses
  OpenLanes__CLI__App__Start ..> OpenLanes__Error : uses
  OpenLanes__CLI__App__Start ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__CLI__App__Start ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__CLI__App__Start ..> OpenLanes__UI : uses
  OpenLanes__CLI__App__Status ..|> OpenLanes__CLI__App__Registry : includes
  OpenLanes__CLI__App__Status --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__App__Status ..> OpenLanes__UI : uses
  OpenLanes__CLI__App__Stop ..|> OpenLanes__CLI__App__Registry : includes
  OpenLanes__CLI__App__Stop --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__App__Stop ..> OpenLanes__UI : uses
  OpenLanes__CLI__Base ..> OpenLanes__Config : uses
  OpenLanes__CLI__Base ..> OpenLanes__Error : uses
  OpenLanes__CLI__Base ..|> OpenLanes__UI : includes
  OpenLanes__CLI__Base ..> OpenLanes__Web__AdminAuth : uses
  OpenLanes__CLI__Base ..> OpenLanes__Web__AdminAuth__Invalid : uses
  OpenLanes__CLI__Base ..> OpenLanes__Web__Listen : uses
  OpenLanes__CLI__Base ..> OpenLanes__Web__Listen__Invalid : uses
  OpenLanes__CLI__Coverage --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Coverage ..> OpenLanes__Config : uses
  OpenLanes__CLI__Coverage ..> OpenLanes__Coverage__Config : uses
  OpenLanes__CLI__Coverage ..> OpenLanes__Coverage__Invalid : uses
  OpenLanes__CLI__Coverage ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__CLI__Create --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Create ..> OpenLanes__Plans__Spec : uses
  OpenLanes__CLI__Docs --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Eval --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Eval ..> OpenLanes__Evals__Invalid : uses
  OpenLanes__CLI__Eval ..> OpenLanes__Evals__Live : uses
  OpenLanes__CLI__Eval ..> OpenLanes__Evals__Run : uses
  OpenLanes__CLI__Eval ..> OpenLanes__Plans__Spec : uses
  OpenLanes__CLI__Eval ..> OpenLanes__UI : uses
  OpenLanes__CLI__Events__Report --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Events__Report ..> OpenLanes__Config : uses
  OpenLanes__CLI__Events__Report ..> OpenLanes__Presentation__EventsReport : uses
  OpenLanes__CLI__Index --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Init --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Init ..> OpenLanes__Config : uses
  OpenLanes__CLI__Init ..> OpenLanes__Error : uses
  OpenLanes__CLI__Init ..> OpenLanes__Plans__Spec : uses
  OpenLanes__CLI__Init ..> OpenLanes__Setup__CiScaffold : uses
  OpenLanes__CLI__Init ..> OpenLanes__Setup__Stack : uses
  OpenLanes__CLI__Init ..> OpenLanes__Setup__StackDocument : uses
  OpenLanes__CLI__Init ..> OpenLanes__UI : uses
  OpenLanes__CLI__Linear__Import --|> OpenLanes__CLI__Linear__Team : inherits
  OpenLanes__CLI__Linear__Import ..> OpenLanes__Error : uses
  OpenLanes__CLI__Linear__Import ..> OpenLanes__Linear__API : uses
  OpenLanes__CLI__Linear__Import ..> OpenLanes__Linear__Import : uses
  OpenLanes__CLI__Linear__Projects --|> OpenLanes__CLI__Linear__Team : inherits
  OpenLanes__CLI__Linear__Projects ..> OpenLanes__Error : uses
  OpenLanes__CLI__Linear__Team --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Linear__Team ..> OpenLanes__Linear__API : uses
  OpenLanes__CLI__Linear__Team ..> OpenLanes__Linear__Survey : uses
  OpenLanes__CLI__Linear__Team ..> OpenLanes__UI : uses
  OpenLanes__CLI__Link --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Link ..> OpenLanes__Error : uses
  OpenLanes__CLI__ListPlans --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Mail__Ack --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Mail__Ack ..|> OpenLanes__CLI__Mail__Locating : includes
  OpenLanes__CLI__Mail__Ack ..> OpenLanes__Error : uses
  OpenLanes__CLI__Mail__Ack ..> OpenLanes__Plans__Mailbox : uses
  OpenLanes__CLI__Mail__Ack ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__CLI__Mail__Ack ..> OpenLanes__UI : uses
  OpenLanes__CLI__Mail__Locating ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__CLI__Mail__Read --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Mail__Read ..|> OpenLanes__CLI__Mail__Locating : includes
  OpenLanes__CLI__Mail__Read ..> OpenLanes__UI : uses
  OpenLanes__CLI__Mail__Render --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Mail__Render ..|> OpenLanes__CLI__Mail__Locating : includes
  OpenLanes__CLI__Mail__Send --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Mail__Send ..|> OpenLanes__CLI__Mail__Locating : includes
  OpenLanes__CLI__Mail__Send ..> OpenLanes__Config : uses
  OpenLanes__CLI__Mail__Send ..> OpenLanes__Error : uses
  OpenLanes__CLI__Mail__Send ..> OpenLanes__Live__Mail : uses
  OpenLanes__CLI__Mail__Send ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__CLI__Mail__Send ..> OpenLanes__Plans__Feature : uses
  OpenLanes__CLI__Mail__Send ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__CLI__Mail__Send ..> OpenLanes__UI : uses
  OpenLanes__CLI__Resync__Dirs --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Resync__Prs --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Review --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Review ..> OpenLanes__Error : uses
  OpenLanes__CLI__Review ..> OpenLanes__Plans__ReviewLabel : uses
  OpenLanes__CLI__Run --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Run ..> OpenLanes__Engine__RunWorkflow : uses
  OpenLanes__CLI__Setup --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Skills__Install --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Start --|> OpenLanes__CLI__Run : inherits
  OpenLanes__CLI__Start ..> OpenLanes__Engine__Dispatcher : uses
  OpenLanes__CLI__State__Locating ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__CLI__State__Locating ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__CLI__State__Resume --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__State__Resume ..|> OpenLanes__CLI__State__Locating : includes
  OpenLanes__CLI__State__Resume ..> OpenLanes__Error : uses
  OpenLanes__CLI__State__Resume ..> OpenLanes__Plans__LastKnownState : uses
  OpenLanes__CLI__State__Resume ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__CLI__State__Resume ..> OpenLanes__UI : uses
  OpenLanes__CLI__State__Show --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__State__Show ..|> OpenLanes__CLI__State__Locating : includes
  OpenLanes__CLI__State__Sign --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__State__Sign ..|> OpenLanes__CLI__State__Locating : includes
  OpenLanes__CLI__State__Sign ..> OpenLanes__Error : uses
  OpenLanes__CLI__State__Sign ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__CLI__State__Sign ..> OpenLanes__UI : uses
  OpenLanes__CLI__Unblock --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Unblock ..> OpenLanes__Lifecycle__UnblockWorkflow : uses
  OpenLanes__CLI__Web --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Web ..> OpenLanes__Config : uses
  OpenLanes__CLI__Web ..> OpenLanes__Live__Copilot__Operator : uses
  OpenLanes__CLI__Web ..> OpenLanes__Live__Node : uses
  OpenLanes__CLI__Web ..> OpenLanes__Live__Node__Invalid : uses
  OpenLanes__CLI__Web ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__CLI__Web ..> OpenLanes__Log__Invalid : uses
  OpenLanes__CLI__Web ..> OpenLanes__Log__Settings : uses
  OpenLanes__CLI__Web ..> OpenLanes__Web__Demo : uses
  OpenLanes__CLI__Web ..> OpenLanes__Web__Launcher : uses
  OpenLanes__CLI__Web ..> OpenLanes__Web__Stores : uses
  OpenLanes__CLI__Worktree --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__Worktree ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__CLI__WorktreePrune --|> OpenLanes__CLI__Base : inherits
  OpenLanes__CLI__WorktreePrune ..> OpenLanes__Error : uses
  OpenLanes__CLI__WorktreePrune ..> OpenLanes__UI : uses
  OpenLanes__CLI__WorktreePrune ..> OpenLanes__Vcs__Worktree : uses
```
