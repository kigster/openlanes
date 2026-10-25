<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Execution

```mermaid
classDiagram
  class OpenLanes__Adapters__Invocation["OpenLanes::Adapters::Invocation"]
  class OpenLanes__Agents__Profile["OpenLanes::Agents::Profile"]
  class OpenLanes__Config["OpenLanes::Config"]
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Execution__Boundary__Snapshot["Boundary::Snapshot"]
  class OpenLanes__Execution__Child["Child"]
  class OpenLanes__Execution__Clock["Clock"]
  class OpenLanes__Execution__Executor["Executor"]
  class OpenLanes__Execution__Executor__Handle["Executor::Handle"]
  class OpenLanes__Execution__Executor__Sessions["Executor::Sessions"]
  class OpenLanes__Execution__Prompt["Prompt"]
  class OpenLanes__Execution__Transcript["Transcript"]
  class OpenLanes__Plans__PlanState["OpenLanes::Plans::PlanState"]
  class OpenLanes__Plans__Spec["OpenLanes::Plans::Spec"]
  class OpenLanes__UI["OpenLanes::UI"]
  <<module>> OpenLanes__UI
  OpenLanes__Execution__Child ..> OpenLanes__UI : uses
  OpenLanes__Execution__Clock ..> OpenLanes__UI : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Adapters__Invocation : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Agents__Profile : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Execution__Child : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Execution__Clock : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Execution__Executor__Handle : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Execution__Executor__Sessions : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Execution__Prompt : uses
  OpenLanes__Execution__Executor ..> OpenLanes__Plans__Spec : uses
  OpenLanes__Execution__Executor ..> OpenLanes__UI : uses
  OpenLanes__Execution__Executor__Handle ..> OpenLanes__Execution__Executor : uses
  OpenLanes__Execution__Prompt ..> OpenLanes__Config : uses
  OpenLanes__Execution__Prompt ..> OpenLanes__Error : uses
  OpenLanes__Execution__Prompt ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__Execution__Prompt ..> OpenLanes__Plans__Spec : uses
```
