<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Apps

```mermaid
classDiagram
  class OpenLanes__Apps__Definition["Definition"]
  class OpenLanes__Apps__Ports["Ports"]
  class OpenLanes__Apps__Ports__Exhausted["Ports::Exhausted"]
  class OpenLanes__Apps__ProcessSpec["ProcessSpec"]
  class OpenLanes__Apps__Runner["Runner"]
  class OpenLanes__Apps__Status["Status"]
  class OpenLanes__Apps__Supervisor["Supervisor"]
  class OpenLanes__Apps__Supervisor__StartFailed["Supervisor::StartFailed"]
  class OpenLanes__Apps__Watcher["Watcher"]
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Execution__Child["OpenLanes::Execution::Child"]
  class OpenLanes__Live__Unavailable["OpenLanes::Live::Unavailable"]
  class OpenLanes__UI["OpenLanes::UI"]
  <<module>> OpenLanes__UI
  OpenLanes__Apps__Definition ..> OpenLanes__Apps__ProcessSpec : uses
  OpenLanes__Apps__Definition ..> OpenLanes__Error : uses
  OpenLanes__Apps__Ports ..> OpenLanes__Apps__Ports__Exhausted : uses
  OpenLanes__Apps__Ports ..> OpenLanes__Apps__Status : uses
  OpenLanes__Apps__Ports ..> OpenLanes__Error : uses
  OpenLanes__Apps__Ports__Exhausted --|> OpenLanes__Error : inherits
  OpenLanes__Apps__Runner ..> OpenLanes__Apps__Supervisor : uses
  OpenLanes__Apps__Runner ..> OpenLanes__Apps__Supervisor__StartFailed : uses
  OpenLanes__Apps__Runner ..> OpenLanes__Apps__Watcher : uses
  OpenLanes__Apps__Runner ..> OpenLanes__Live__Unavailable : uses
  OpenLanes__Apps__Supervisor ..> OpenLanes__Apps__Ports : uses
  OpenLanes__Apps__Supervisor ..> OpenLanes__Apps__Status : uses
  OpenLanes__Apps__Supervisor ..> OpenLanes__Apps__Supervisor__StartFailed : uses
  OpenLanes__Apps__Supervisor ..> OpenLanes__Error : uses
  OpenLanes__Apps__Supervisor ..> OpenLanes__Execution__Child : uses
  OpenLanes__Apps__Supervisor ..> OpenLanes__UI : uses
  OpenLanes__Apps__Supervisor__StartFailed --|> OpenLanes__Error : inherits
```
