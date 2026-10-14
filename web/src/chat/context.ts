// The chat as the tabs, the dialogs and the panel share it (ChatRoom provides it).
import { createContext, useContext } from "react";
import type { ChatInvite, Node } from "../api/types";
import type { Chat } from "./useChat";

/** What the Name dialog is asked for: a new chat with a machine, or joining the chat an invite names. */
export type NameRequest = { kind: "start"; machine: string; label: string } | { kind: "accept"; invite: ChatInvite };

export interface ChatUi {
  chat: Chat;
  /** Opens the Name dialog for a start or an accepted invite. */
  askName(request: NameRequest): void;
}

export const ChatContext = createContext<ChatUi | null>(null);

/** The chat, or null where there is none (`?fixture`, or outside ChatRoom). */
export function useChatUi(): ChatUi | null {
  return useContext(ChatContext);
}

export type MenuItem = "start" | "invite" | "inviting" | "stop";

/**
 * What a machine's menu offers (D3, D5): Start Chat outside a chat; in one, Stop Chat on a machine already in it, and
 * Invite to Chat (or the invite still waiting) beside Stop Chat on one that is not.
 */
export function menuItems(chat: Pick<Chat, "room" | "outgoing">, node: Pick<Node, "id">): MenuItem[] {
  if (!chat.room) return ["start"];
  if (chat.room.participants.some(p => p.machine === node.id)) return ["stop"];
  return [chat.outgoing.some(o => o.machine === node.id) ? "inviting" : "invite", "stop"];
}
