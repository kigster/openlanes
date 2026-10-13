// The chat between machines (plan 006) on the page: the menu on each other machine's tab (D3), the Name dialog (D8),
// the invite modal (D4, D9) and the orange panel docked bottom left (D11). One provider holds the chat, so the tabs,
// the dialogs and the panel never disagree about who is in it.
import { useCallback, useMemo, useState, type ReactNode } from "react";
import type { ChatInvite } from "../api/types";
import { ChatPanel } from "./ChatPanel";
import { ChatContext, type NameRequest } from "./context";
import { InviteDialog, NameDialog } from "./dialogs";
import { useChat } from "./useChat";
import "./chat.css";

export interface ChatRoomProps {
  /** This machine's user: the Name dialog's first suggestion (D8). */
  user: string;
  /** False under `?fixture`, where nothing is connected to chat with: no menus, no panel. */
  enabled?: boolean;
  children: ReactNode;
}

export function ChatRoom({ user, enabled = true, children }: ChatRoomProps) {
  const chat = useChat(enabled);
  const [naming, setNaming] = useState<NameRequest | null>(null);
  const askName = useCallback((request: NameRequest) => setNaming(request), []);
  const ui = useMemo(() => (enabled ? { chat, askName } : null), [enabled, chat, askName]);
  const invite = naming ? null : (chat.invites[0] ?? null);
  // An invite answered elsewhere or expired while its Name dialog was open: the dialog has nothing left to join.
  const accepting = naming?.kind === "accept" ? naming.invite : null;
  const stale = accepting !== null && !chat.invites.some(i => i.id === accepting.id);

  return (
    <ChatContext.Provider value={ui}>
      {children}
      {ui && (
        <>
          <NameDialog
            request={naming}
            user={user}
            gone={stale ? "That invite is no longer open: it was answered on another page, or it expired." : null}
            onCancel={() => {
              if (naming?.kind === "accept") void chat.decline(naming.invite);
              setNaming(null);
            }}
            onConfirm={async name => {
              if (!naming) return;
              if (naming.kind === "start") await chat.start(naming.machine, naming.label, name);
              else await chat.accept(naming.invite, name);
              setNaming(null);
            }}
          />
          <InviteDialog
            invite={invite}
            inChat={chat.room !== null}
            onDecline={(i: ChatInvite) => void chat.decline(i)}
            onAccept={(i: ChatInvite) => setNaming({ kind: "accept", invite: i })}
          />
          {chat.room && <ChatPanel chat={chat} />}
        </>
      )}
    </ChatContext.Provider>
  );
}
