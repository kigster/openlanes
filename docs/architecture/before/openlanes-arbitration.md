<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Arbitration

```mermaid
classDiagram
  class OpenLanes__Arbitration__Appeal["Appeal"]
  class OpenLanes__Arbitration__Counter["Counter"]
  class OpenLanes__Arbitration__Effects["Effects"]
  class OpenLanes__Arbitration__Ruling["Ruling"]
  class OpenLanes__Arbitration__Ruling__Ambiguous["Ruling::Ambiguous"]
  class OpenLanes__Arbitration__Ruling__IllegalOutcome["Ruling::IllegalOutcome"]
  class OpenLanes__Arbitration__Ruling__Missing["Ruling::Missing"]
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Plans__Mailbox["OpenLanes::Plans::Mailbox"]
  class OpenLanes__Plans__PlanState["OpenLanes::Plans::PlanState"]
  class OpenLanes__Plans__ReviewLabel["OpenLanes::Plans::ReviewLabel"]
  class OpenLanes__Plans__StateMachine["OpenLanes::Plans::StateMachine"]
  class OpenLanes__Plans__StateMachine__Refused["OpenLanes::Plans::StateMachine::Refused"]
  class OpenLanes__Plans__Tree["OpenLanes::Plans::Tree"]
  class OpenLanes__Vcs__GitHub["OpenLanes::Vcs::GitHub"]
  class OpenLanes__Vcs__Review["OpenLanes::Vcs::Review"]
  OpenLanes__Arbitration__Counter ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Error : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Plans__Mailbox : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Plans__PlanState : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Plans__ReviewLabel : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Plans__StateMachine : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Plans__StateMachine__Refused : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Plans__Tree : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Vcs__GitHub : uses
  OpenLanes__Arbitration__Effects ..> OpenLanes__Vcs__Review : uses
  OpenLanes__Arbitration__Ruling ..> OpenLanes__Arbitration__Ruling__Ambiguous : uses
  OpenLanes__Arbitration__Ruling ..> OpenLanes__Arbitration__Ruling__IllegalOutcome : uses
  OpenLanes__Arbitration__Ruling ..> OpenLanes__Arbitration__Ruling__Missing : uses
  OpenLanes__Arbitration__Ruling ..> OpenLanes__Error : uses
  OpenLanes__Arbitration__Ruling__Ambiguous --|> OpenLanes__Error : inherits
  OpenLanes__Arbitration__Ruling__IllegalOutcome --|> OpenLanes__Error : inherits
  OpenLanes__Arbitration__Ruling__Missing --|> OpenLanes__Error : inherits
```
