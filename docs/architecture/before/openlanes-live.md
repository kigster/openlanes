<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Live

```mermaid
classDiagram
  class OpenLanes__Adapters__Invocation["OpenLanes::Adapters::Invocation"]
  class OpenLanes__Agents__Profile["OpenLanes::Agents::Profile"]
  class OpenLanes__Config["OpenLanes::Config"]
  class OpenLanes__Engine__Board["OpenLanes::Engine::Board"]
  class OpenLanes__Engine__Extensions["OpenLanes::Engine::Extensions"]
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Execution__Child["OpenLanes::Execution::Child"]
  class OpenLanes__Execution__Executor["OpenLanes::Execution::Executor"]
  class OpenLanes__Lifecycle__Aging["OpenLanes::Lifecycle::Aging"]
  class OpenLanes__Lifecycle__Creator["OpenLanes::Lifecycle::Creator"]
  class OpenLanes__Lifecycle__Unblocker["OpenLanes::Lifecycle::Unblocker"]
  class OpenLanes__Live__Chat["Chat"]
  class OpenLanes__Live__Chat__Invalid["Chat::Invalid"]
  class OpenLanes__Live__Chat__Settled["Chat::Settled"]
  class OpenLanes__Live__ChoiceConverter["ChoiceConverter"]
  class OpenLanes__Live__ChoiceConverter__Invalid["ChoiceConverter::Invalid"]
  class OpenLanes__Live__ChoiceJudge["ChoiceJudge"]
  class OpenLanes__Live__Claims["Claims"]
  class OpenLanes__Live__Command["Command"]
  class OpenLanes__Live__Command__Invalid["Command::Invalid"]
  class OpenLanes__Live__Commands["Commands"]
  class OpenLanes__Live__Commands__Refusal["Commands::Refusal"]
  class OpenLanes__Live__Copilot["Copilot"]
  class OpenLanes__Live__Copilot__Brief["Copilot::Brief"]
  class OpenLanes__Live__Copilot__Invalid["Copilot::Invalid"]
  class OpenLanes__Live__Copilot__Operator["Copilot::Operator"]
  class OpenLanes__Live__Copilot__Slash__Help["Copilot::Slash::Help"]
  class OpenLanes__Live__Copilot__Turn["Copilot::Turn"]
  class OpenLanes__Live__Copilot__Unanswered["Copilot::Unanswered"]
  class OpenLanes__Live__EventBus__Base["EventBus::Base"]
  class OpenLanes__Live__EventBus__MemoryBus["EventBus::MemoryBus"]
  class OpenLanes__Live__EventBus__RedisBus["EventBus::RedisBus"]
  class OpenLanes__Live__EventBus__Transaction["EventBus::Transaction"]
  class OpenLanes__Live__GroupMissing["GroupMissing"]
  class OpenLanes__Live__Interviewer["Interviewer"]
  class OpenLanes__Live__Keys["Keys"]
  class OpenLanes__Live__Mail["Mail"]
  class OpenLanes__Live__MemoryStore["MemoryStore"]
  class OpenLanes__Live__MemorySubscriber["MemorySubscriber"]
  class OpenLanes__Live__Meter["Meter"]
  class OpenLanes__Live__Node["Node"]
  class OpenLanes__Live__Node__Invalid["Node::Invalid"]
  class OpenLanes__Live__Outage["Outage"]
  class OpenLanes__Live__OutageReport["OutageReport"]
  class OpenLanes__Live__Publisher["Publisher"]
  class OpenLanes__Live__Reply["Reply"]
  class OpenLanes__Live__RunRecord["RunRecord"]
  class OpenLanes__Live__RunState["RunState"]
  class OpenLanes__Live__Session["Session"]
  class OpenLanes__Live__Snapshot["Snapshot"]
  class OpenLanes__Live__Stations__Station["Stations::Station"]
  class OpenLanes__Live__Store["Store"]
  class OpenLanes__Live__Store__Transaction["Store::Transaction"]
  class OpenLanes__Live__Subscriber["Subscriber"]
  class OpenLanes__Live__Unavailable["Unavailable"]
  class OpenLanes__Plans__Choices["OpenLanes::Plans::Choices"]
  class OpenLanes__Plans__Feature["OpenLanes::Plans::Feature"]
  class OpenLanes__Plans__Lock["OpenLanes::Plans::Lock"]
  class OpenLanes__Plans__Mailbox["OpenLanes::Plans::Mailbox"]
  class OpenLanes__Plans__Ordinal["OpenLanes::Plans::Ordinal"]
  class OpenLanes__Plans__PlanState["OpenLanes::Plans::PlanState"]
  class OpenLanes__Plans__Spec["OpenLanes::Plans::Spec"]
  class OpenLanes__UI["OpenLanes::UI"]
  <<module>> OpenLanes__UI
  OpenLanes__Live__Chat ..> OpenLanes__Error : uses
  OpenLanes__Live__Chat ..> OpenLanes__Live__Chat__Invalid : uses
  OpenLanes__Live__Chat ..> OpenLanes__Live__Chat__Settled : uses
  OpenLanes__Live__Chat ..> OpenLanes__Live__Command : uses
  OpenLanes__Live__Chat ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Chat ..> OpenLanes__UI : uses
  OpenLanes__Live__Chat__Invalid --|> OpenLanes__Error : inherits
  OpenLanes__Live__Chat__Settled --|> OpenLanes__Error : inherits
  OpenLanes__Live__ChoiceConverter ..> OpenLanes__Config : uses
  OpenLanes__Live__ChoiceConverter ..> OpenLanes__Error : uses
  OpenLanes__Live__ChoiceConverter ..> OpenLanes__Live__ChoiceConverter__Invalid : uses
  OpenLanes__Live__ChoiceConverter ..> OpenLanes__Plans__Choices : uses
  OpenLanes__Live__ChoiceConverter__Invalid --|> OpenLanes__Error : inherits
  OpenLanes__Live__ChoiceJudge ..> OpenLanes__UI : uses
  OpenLanes__Live__Claims ..> OpenLanes__Live__Keys : uses
  OpenLanes__Live__Command ..> OpenLanes__Error : uses
  OpenLanes__Live__Command ..> OpenLanes__Live__Command__Invalid : uses
  OpenLanes__Live__Command ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__Live__Command__Invalid --|> OpenLanes__Error : inherits
  OpenLanes__Live__Commands ..> OpenLanes__Config : uses
  OpenLanes__Live__Commands ..> OpenLanes__Error : uses
  OpenLanes__Live__Commands ..> OpenLanes__Lifecycle__Creator : uses
  OpenLanes__Live__Commands ..> OpenLanes__Lifecycle__Unblocker : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Command : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Command__Invalid : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Commands__Refusal : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Copilot : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__GroupMissing : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Keys : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Reply : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__RunState : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Snapshot : uses
  OpenLanes__Live__Commands ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Commands ..> OpenLanes__Plans__Feature : uses
  OpenLanes__Live__Commands ..> OpenLanes__Plans__Mailbox : uses
  OpenLanes__Live__Commands ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__Live__Commands ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__Live__Commands ..> OpenLanes__UI : uses
  OpenLanes__Live__Copilot ..> OpenLanes__Error : uses
  OpenLanes__Live__Copilot ..> OpenLanes__Live__Command : uses
  OpenLanes__Live__Copilot ..> OpenLanes__Live__Copilot__Invalid : uses
  OpenLanes__Live__Copilot ..> OpenLanes__Live__Copilot__Slash__Help : uses
  OpenLanes__Live__Copilot ..> OpenLanes__Live__Copilot__Unanswered : uses
  OpenLanes__Live__Copilot ..> OpenLanes__Live__Keys : uses
  OpenLanes__Live__Copilot__Invalid --|> OpenLanes__Error : inherits
  OpenLanes__Live__Copilot__Operator ..> OpenLanes__Adapters__Invocation : uses
  OpenLanes__Live__Copilot__Operator ..> OpenLanes__Agents__Profile : uses
  OpenLanes__Live__Copilot__Operator ..> OpenLanes__Error : uses
  OpenLanes__Live__Copilot__Operator ..> OpenLanes__Execution__Child : uses
  OpenLanes__Live__Copilot__Operator ..> OpenLanes__Execution__Executor : uses
  OpenLanes__Live__Copilot__Operator ..> OpenLanes__Live__Copilot : uses
  OpenLanes__Live__Copilot__Operator ..> OpenLanes__Live__Copilot__Brief : uses
  OpenLanes__Live__Copilot__Turn ..> OpenLanes__Live__Command : uses
  OpenLanes__Live__Copilot__Turn ..> OpenLanes__Live__Command__Invalid : uses
  OpenLanes__Live__Copilot__Turn ..> OpenLanes__Live__Copilot__Invalid : uses
  OpenLanes__Live__Copilot__Unanswered --|> OpenLanes__Error : inherits
  OpenLanes__Live__EventBus__Base ..> OpenLanes__Live__EventBus__Transaction : uses
  OpenLanes__Live__EventBus__MemoryBus --|> OpenLanes__Live__EventBus__Base : inherits
  OpenLanes__Live__EventBus__MemoryBus ..> OpenLanes__Live__MemoryStore : uses
  OpenLanes__Live__EventBus__RedisBus --|> OpenLanes__Live__EventBus__Base : inherits
  OpenLanes__Live__EventBus__Transaction ..> OpenLanes__Live__Store : uses
  OpenLanes__Live__GroupMissing --|> OpenLanes__Error : inherits
  OpenLanes__Live__Interviewer ..> OpenLanes__Config : uses
  OpenLanes__Live__Interviewer ..> OpenLanes__Live__ChoiceConverter : uses
  OpenLanes__Live__Interviewer ..> OpenLanes__Live__ChoiceConverter__Invalid : uses
  OpenLanes__Live__Interviewer ..> OpenLanes__Plans__Choices : uses
  OpenLanes__Live__Mail ..> OpenLanes__Live__Keys : uses
  OpenLanes__Live__MemoryStore ..> OpenLanes__Live__GroupMissing : uses
  OpenLanes__Live__MemoryStore ..> OpenLanes__Live__MemorySubscriber : uses
  OpenLanes__Live__MemoryStore ..> OpenLanes__Live__Store : uses
  OpenLanes__Live__MemoryStore ..> OpenLanes__Live__Store__Transaction : uses
  OpenLanes__Live__Node ..> OpenLanes__Live__Node__Invalid : uses
  OpenLanes__Live__Outage ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Outage ..> OpenLanes__UI : uses
  OpenLanes__Live__OutageReport ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Publisher ..> OpenLanes__Live__Keys : uses
  OpenLanes__Live__Publisher ..> OpenLanes__Live__Meter : uses
  OpenLanes__Live__Publisher ..> OpenLanes__Live__RunState : uses
  OpenLanes__Live__Publisher ..> OpenLanes__Live__Snapshot : uses
  OpenLanes__Live__Publisher ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Publisher ..> OpenLanes__UI : uses
  OpenLanes__Live__RunRecord ..> OpenLanes__Error : uses
  OpenLanes__Live__RunRecord ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__RunRecord ..> OpenLanes__UI : uses
  OpenLanes__Live__Session ..> OpenLanes__Config : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Claims : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Commands : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Keys : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Mail : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Node : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Outage : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__OutageReport : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Publisher : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__RunRecord : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__RunState : uses
  OpenLanes__Live__Session ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Session ..> OpenLanes__UI : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Config : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Engine__Board : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Engine__Extensions : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Error : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Lifecycle__Aging : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Lifecycle__Unblocker : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Live__Meter : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Live__RunState : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Plans__Choices : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Plans__Lock : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__Live__Snapshot ..> OpenLanes__Plans__Spec : uses
  OpenLanes__Live__Store ..> OpenLanes__Live__GroupMissing : uses
  OpenLanes__Live__Store ..> OpenLanes__Live__Store__Transaction : uses
  OpenLanes__Live__Store ..> OpenLanes__Live__Subscriber : uses
  OpenLanes__Live__Store ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Subscriber ..> OpenLanes__Live__Store : uses
  OpenLanes__Live__Subscriber ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Live__Unavailable --|> OpenLanes__Error : inherits
```
