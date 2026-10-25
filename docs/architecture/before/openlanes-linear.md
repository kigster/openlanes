<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Linear

```mermaid
classDiagram
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Linear__API["API"]
  class OpenLanes__Linear__Action["Action"]
  class OpenLanes__Linear__Attribution["Attribution"]
  class OpenLanes__Linear__Import["Import"]
  class OpenLanes__Linear__Issue["Issue"]
  class OpenLanes__Linear__Issues["Issues"]
  class OpenLanes__Linear__Placement["Placement"]
  class OpenLanes__Linear__Push["Push"]
  class OpenLanes__Linear__Result["Result"]
  class OpenLanes__Linear__Survey["Survey"]
  class OpenLanes__Linear__Unit["Unit"]
  class OpenLanes__Linear__Units["Units"]
  class OpenLanes__Plans__Ordinal["OpenLanes::Plans::Ordinal"]
  OpenLanes__Linear__API ..> OpenLanes__Error : uses
  OpenLanes__Linear__Import ..> OpenLanes__Linear__Action : uses
  OpenLanes__Linear__Import ..> OpenLanes__Linear__Issues : uses
  OpenLanes__Linear__Import ..> OpenLanes__Linear__Unit : uses
  OpenLanes__Linear__Import ..> OpenLanes__Linear__Units : uses
  OpenLanes__Linear__Import ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__Linear__Issues ..> OpenLanes__Linear__Issue : uses
  OpenLanes__Linear__Push ..> OpenLanes__Error : uses
  OpenLanes__Linear__Push ..> OpenLanes__Linear__Issue : uses
  OpenLanes__Linear__Push ..> OpenLanes__Linear__Issues : uses
  OpenLanes__Linear__Push ..> OpenLanes__Linear__Result : uses
  OpenLanes__Linear__Survey ..> OpenLanes__Error : uses
  OpenLanes__Linear__Units ..> OpenLanes__Linear__Unit : uses
```
