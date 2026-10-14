// The ▾ beside another machine's tab (D3): Start Chat, Invite to Chat or Stop Chat, whichever applies. A right-click
// on the tab opens the same menu; a plain click on the tab still opens that machine's board.
import * as Menu from "@radix-ui/react-dropdown-menu";
import type { Node } from "../api/types";
import { who } from "../board/format";
import { menuItems, useChatUi } from "./context";

export interface MachineMenuProps {
  node: Pick<Node, "id" | "user" | "host">;
  open: boolean;
  onOpenChange(open: boolean): void;
}

export function MachineMenu({ node, open, onOpenChange }: MachineMenuProps) {
  const ui = useChatUi();
  if (!ui) return null;
  const { chat, askName } = ui;
  const label = who(node);
  const items = menuItems(chat, node);
  // A failed invite or leave says why in the conversation, where the person is looking.
  const failed = (what: string) => (error: unknown) => chat.note(`${what}: ${error instanceof Error ? error.message : String(error)}`);

  return (
    <Menu.Root open={open} onOpenChange={onOpenChange} modal={false}>
      <Menu.Trigger className="tab-caret" aria-label={`Chat with ${label}`} title={`Chat with ${label}`}>
        <span aria-hidden="true">▾</span>
      </Menu.Trigger>
      <Menu.Portal>
        <Menu.Content className="menu chat-menu" align="end" sideOffset={6} loop>
          {items.includes("start") && (
            <Menu.Item className="menu-item" onSelect={() => askName({ kind: "start", machine: node.id, label })}>
              <span className="menu-title">Start Chat</span>
              <span className="menu-sub">with {label}</span>
            </Menu.Item>
          )}
          {items.includes("invite") && (
            <Menu.Item className="menu-item" onSelect={() => void chat.invite(node.id, label).catch(failed(`Could not invite ${label}`))}>
              <span className="menu-title">Invite to Chat</span>
              <span className="menu-sub">{label} joins the chat you are in</span>
            </Menu.Item>
          )}
          {items.includes("inviting") && (
            <Menu.Item className="menu-item" disabled>
              <span className="menu-title">Invite to Chat</span>
              <span className="menu-sub">Waiting for {label} to answer</span>
            </Menu.Item>
          )}
          {items.includes("stop") && (
            <Menu.Item className="menu-item" onSelect={() => void chat.leave().catch(failed("Could not leave the chat"))}>
              <span className="menu-title">Stop Chat</span>
              <span className="menu-sub">Leave it; the others carry on</span>
            </Menu.Item>
          )}
        </Menu.Content>
      </Menu.Portal>
    </Menu.Root>
  );
}
