<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Events

```mermaid
classDiagram
  class OpenLanes__Events__Event["Event"]
  class OpenLanes__Events__Log["Log"]
  class OpenLanes__Events__NullSink["NullSink"]
  class OpenLanes__Events__Report["Report"]
  class OpenLanes__Events__Sink["Sink"]
  class OpenLanes__Events__Usage["Usage"]
  OpenLanes__Events__Log ..> OpenLanes__Events__Event : uses
  OpenLanes__Events__Sink ..> OpenLanes__Events__Event : uses
```
