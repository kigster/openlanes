<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Web

```mermaid
classDiagram
  class OpenLanes__Apps__Definition["OpenLanes::Apps::Definition"]
  class OpenLanes__Apps__Runner["OpenLanes::Apps::Runner"]
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Live__Chat["OpenLanes::Live::Chat"]
  class OpenLanes__Live__Chat__Invalid["OpenLanes::Live::Chat::Invalid"]
  class OpenLanes__Live__Chat__Settled["OpenLanes::Live::Chat::Settled"]
  class OpenLanes__Live__Command["OpenLanes::Live::Command"]
  class OpenLanes__Live__Command__Invalid["OpenLanes::Live::Command::Invalid"]
  class OpenLanes__Live__Commands["OpenLanes::Live::Commands"]
  class OpenLanes__Live__Copilot["OpenLanes::Live::Copilot"]
  class OpenLanes__Live__Copilot__Invalid["OpenLanes::Live::Copilot::Invalid"]
  class OpenLanes__Live__Copilot__Unanswered["OpenLanes::Live::Copilot::Unanswered"]
  class OpenLanes__Live__Keys["OpenLanes::Live::Keys"]
  class OpenLanes__Live__Node["OpenLanes::Live::Node"]
  class OpenLanes__Live__Reply["OpenLanes::Live::Reply"]
  class OpenLanes__Live__Unavailable["OpenLanes::Live::Unavailable"]
  class OpenLanes__Plans__Ordinal["OpenLanes::Plans::Ordinal"]
  class OpenLanes__UI["OpenLanes::UI"]
  <<module>> OpenLanes__UI
  class OpenLanes__Web__AdminAuth["AdminAuth"]
  class OpenLanes__Web__AdminAuth__Invalid["AdminAuth::Invalid"]
  class OpenLanes__Web__App["App"]
  class OpenLanes__Web__Context["Context"]
  class OpenLanes__Web__Demo["Demo"]
  class OpenLanes__Web__DemoBoard["DemoBoard"]
  class OpenLanes__Web__DemoBoard__Refusal["DemoBoard::Refusal"]
  class OpenLanes__Web__Events["Events"]
  class OpenLanes__Web__Launcher["Launcher"]
  class OpenLanes__Web__Listen["Listen"]
  class OpenLanes__Web__Listen__Invalid["Listen::Invalid"]
  class OpenLanes__Web__PlanFiles["PlanFiles"]
  class OpenLanes__Web__PlanFiles__FrontmatterChanged["PlanFiles::FrontmatterChanged"]
  class OpenLanes__Web__PlanFiles__NotFound["PlanFiles::NotFound"]
  class OpenLanes__Web__PlanFiles__ReadOnly["PlanFiles::ReadOnly"]
  class OpenLanes__Web__PlanFiles__Stale["PlanFiles::Stale"]
  class OpenLanes__Web__RequestLog["RequestLog"]
  class OpenLanes__Web__Server["Server"]
  class OpenLanes__Web__Stores["Stores"]
  OpenLanes__Web__AdminAuth ..> OpenLanes__Error : uses
  OpenLanes__Web__AdminAuth ..> OpenLanes__Web__AdminAuth__Invalid : uses
  OpenLanes__Web__AdminAuth__Invalid --|> OpenLanes__Error : inherits
  OpenLanes__Web__App ..> OpenLanes__Apps__Definition : uses
  OpenLanes__Web__App ..> OpenLanes__Apps__Runner : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Chat__Invalid : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Chat__Settled : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Command : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Command__Invalid : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Copilot__Invalid : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Copilot__Unanswered : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Reply : uses
  OpenLanes__Web__App ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Web__App ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__Web__App ..> OpenLanes__Web__AdminAuth : uses
  OpenLanes__Web__App ..> OpenLanes__Web__Events : uses
  OpenLanes__Web__App ..> OpenLanes__Web__PlanFiles : uses
  OpenLanes__Web__App ..> OpenLanes__Web__PlanFiles__FrontmatterChanged : uses
  OpenLanes__Web__App ..> OpenLanes__Web__PlanFiles__NotFound : uses
  OpenLanes__Web__App ..> OpenLanes__Web__PlanFiles__ReadOnly : uses
  OpenLanes__Web__App ..> OpenLanes__Web__PlanFiles__Stale : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Command : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Command__Invalid : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Commands : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Copilot : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Keys : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Node : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Reply : uses
  OpenLanes__Web__Demo ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Web__Demo ..> OpenLanes__UI : uses
  OpenLanes__Web__Demo ..> OpenLanes__Web__DemoBoard : uses
  OpenLanes__Web__Demo ..> OpenLanes__Web__DemoBoard__Refusal : uses
  OpenLanes__Web__DemoBoard ..> OpenLanes__Live__Commands : uses
  OpenLanes__Web__DemoBoard ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__Web__DemoBoard ..> OpenLanes__Web__DemoBoard__Refusal : uses
  OpenLanes__Web__Events ..> OpenLanes__Live__Chat : uses
  OpenLanes__Web__Events ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Web__Events ..> OpenLanes__UI : uses
  OpenLanes__Web__Launcher ..> OpenLanes__Web__AdminAuth : uses
  OpenLanes__Web__Launcher ..> OpenLanes__Web__Listen : uses
  OpenLanes__Web__Listen ..> OpenLanes__Error : uses
  OpenLanes__Web__Listen ..> OpenLanes__Web__Listen__Invalid : uses
  OpenLanes__Web__Listen__Invalid --|> OpenLanes__Error : inherits
  OpenLanes__Web__PlanFiles ..> OpenLanes__Error : uses
  OpenLanes__Web__PlanFiles ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__Web__PlanFiles ..> OpenLanes__Web__PlanFiles__FrontmatterChanged : uses
  OpenLanes__Web__PlanFiles ..> OpenLanes__Web__PlanFiles__NotFound : uses
  OpenLanes__Web__PlanFiles ..> OpenLanes__Web__PlanFiles__ReadOnly : uses
  OpenLanes__Web__PlanFiles ..> OpenLanes__Web__PlanFiles__Stale : uses
  OpenLanes__Web__PlanFiles__FrontmatterChanged --|> OpenLanes__Error : inherits
  OpenLanes__Web__PlanFiles__NotFound --|> OpenLanes__Error : inherits
  OpenLanes__Web__PlanFiles__ReadOnly --|> OpenLanes__Error : inherits
  OpenLanes__Web__PlanFiles__Stale --|> OpenLanes__Error : inherits
  OpenLanes__Web__Server ..> OpenLanes__Web__Listen : uses
```
