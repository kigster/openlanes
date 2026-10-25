<!-- Generated once by `openlanes uml` from main at a80651d, before the 4.0 refactor. Frozen: do not regenerate or edit. -->

# OpenLanes::Vcs

```mermaid
classDiagram
  class OpenLanes__Error["OpenLanes::Error"]
  class OpenLanes__Events__NullSink["OpenLanes::Events::NullSink"]
  class OpenLanes__Plans__Ordinal["OpenLanes::Plans::Ordinal"]
  class OpenLanes__Plans__ReviewLabel["OpenLanes::Plans::ReviewLabel"]
  class OpenLanes__UI["OpenLanes::UI"]
  <<module>> OpenLanes__UI
  class OpenLanes__Vcs__GitHub["GitHub"]
  class OpenLanes__Vcs__LabelMigration["LabelMigration"]
  class OpenLanes__Vcs__LabelSync["LabelSync"]
  class OpenLanes__Vcs__Mainline["Mainline"]
  class OpenLanes__Vcs__Publisher["Publisher"]
  class OpenLanes__Vcs__Refresh["Refresh"]
  class OpenLanes__Vcs__Review["Review"]
  class OpenLanes__Vcs__Worktree["Worktree"]
  OpenLanes__Vcs__GitHub ..> OpenLanes__Error : uses
  OpenLanes__Vcs__GitHub ..> OpenLanes__UI : uses
  OpenLanes__Vcs__LabelMigration ..> OpenLanes__Error : uses
  OpenLanes__Vcs__LabelMigration ..> OpenLanes__Plans__ReviewLabel : uses
  OpenLanes__Vcs__LabelMigration ..> OpenLanes__UI : uses
  OpenLanes__Vcs__LabelMigration ..> OpenLanes__Vcs__GitHub : uses
  OpenLanes__Vcs__LabelSync ..> OpenLanes__Plans__ReviewLabel : uses
  OpenLanes__Vcs__LabelSync ..> OpenLanes__Vcs__GitHub : uses
  OpenLanes__Vcs__Publisher ..> OpenLanes__Error : uses
  OpenLanes__Vcs__Publisher ..> OpenLanes__Events__NullSink : uses
  OpenLanes__Vcs__Publisher ..> OpenLanes__Plans__Ordinal : uses
  OpenLanes__Vcs__Publisher ..> OpenLanes__Plans__ReviewLabel : uses
  OpenLanes__Vcs__Publisher ..> OpenLanes__Vcs__GitHub : uses
  OpenLanes__Vcs__Refresh ..> OpenLanes__UI : uses
  OpenLanes__Vcs__Review ..> OpenLanes__Plans__ReviewLabel : uses
  OpenLanes__Vcs__Review ..> OpenLanes__Vcs__GitHub : uses
  OpenLanes__Vcs__Worktree ..> OpenLanes__Error : uses
  OpenLanes__Vcs__Worktree ..> OpenLanes__UI : uses
  OpenLanes__Vcs__Worktree ..> OpenLanes__Vcs__Refresh : uses
```
