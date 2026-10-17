// The control room's interactive pieces. They take data shaped by api/types.ts and a command callback; none fetches.
import "./panels.css";

export type { SendCommand } from "./support";
export { AnnouncerProvider, Feedback } from "./feedback";
export { useAnnounce, useCommand, type Outcome } from "./command";
export { AsksProvider } from "./AsksProvider";
export { AskStore } from "./asks";
export { MarkdownEditor, type MarkdownEditorProps } from "./MarkdownEditor";
export { renderMarkdown } from "./markdown";
export { AskCard } from "./AskCard";
export { asksOf, type Ask } from "./question";
export { NeedsYou, type NeedsYouProps } from "./NeedsYou";
export { BombNotice, type BombNoticeProps } from "./BombNotice";
export { PlanDrawer, type PlanDrawerProps } from "./PlanDrawer";
export { PlanFilePopup, type PlanFilePopupProps } from "./PlanFilePopup";
export { UnblockWidget, type UnblockWidgetProps } from "./UnblockWidget";
export { ModelSelect, type ModelSelectProps } from "./ModelSelect";
export { AgentActionMenu, type AgentActionMenuProps, type AgentAction } from "./AgentActionMenu";
export { AgentDrawer, type AgentDrawerProps } from "./AgentDrawer";
export { LastKnownTable } from "./LastKnownTable";
export { ActionMenu, type ActionMenuProps } from "./ActionMenu";
export { IdeaDialog, FrontmatterForm, type IdeaDialogProps } from "./IdeaDialog";
export { IDEA_DEFAULTS, type IdeaFrontmatter } from "./frontmatter";
export { StopAllDialog, HelpDialog, type StopAllDialogProps } from "./dialogs";
