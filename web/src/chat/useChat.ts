// The chat between machines (plan 006), as this page sees it: the chat it is in, what has been said since it joined,
// the invites open to its machine, and the ones it is waiting on. `GET /api/chat` once, then every `event: chat` the
// board's stream relays through the chat bus. Sending is a POST; the server's answer and the stream's echo of it are
// told apart by the message's id.
import { useCallback, useEffect, useReducer, useRef } from "react";
import { ulid } from "ulid";
import { fetchChat, postChat } from "../api/client";
import type { ChatEvent, ChatInvite, ChatOutgoing, ChatParticipant, ChatSaid, ChatState } from "../api/types";
import { chatBus } from "./bus";
import { pageId } from "./page";

/** Characters one message may carry (D10). */
export const LIMIT = 4000;

/** Seconds without typing, sending or clicking in the chat before the others see "<name> is idle" (D7). */
export const IDLE_AFTER_MS = 60_000;

const NAME_KEY = "openlanes-chat-name";

/** The name last used in this browser, or the machine's user on first use (D8). */
export function lastName(fallback: string): string {
  try {
    return localStorage.getItem(NAME_KEY) || fallback;
  } catch {
    return fallback;
  }
}

function keepName(name: string): void {
  try {
    localStorage.setItem(NAME_KEY, name);
  } catch {
    // a private window: asked again, prefilled with the user
  }
}

/** One line of the conversation: something said, or a notice of who came, went, idled or did not answer. */
export type Entry =
  | { type: "said"; id: string; who: ChatParticipant; text: string; at: string; mine: boolean }
  | { type: "notice"; id: string; text: string };

export type Room = NonNullable<ChatState["chat"]>;

export interface ChatView {
  room: Room | null;
  entries: Entry[];
  invites: ChatInvite[];
  outgoing: ChatOutgoing[];
  /** Bumped by every message from someone else, so the panel can show a dot while minimised. */
  heard: number;
  /** Bumped when this page starts or joins a chat, so the panel opens. */
  entered: number;
}

const EMPTY: ChatView = { room: null, entries: [], invites: [], outgoing: [], heard: 0, entered: 0 };

type Action =
  | { type: "loaded"; state: ChatState }
  | { type: "event"; event: ChatEvent }
  | { type: "entered"; state: ChatState; chat: string; me: ChatParticipant }
  | { type: "left" }
  | { type: "said"; said: ChatSaid }
  | { type: "invited"; outgoing: ChatOutgoing }
  | { type: "notice"; text: string }
  | { type: "drop-invite"; id: string };

let notices = 0;
const notice = (text: string): Entry => ({ type: "notice", id: `notice-${++notices}`, text });

/** The participant as the person reads them: "You" for this page. */
const add = (view: ChatView, entry: Entry): ChatView => ({ ...view, entries: [...view.entries, entry] });

/** A server that answered with something else (a test's stub, an old server) reads as no chat at all. */
function asState(data: unknown): ChatState {
  const d = (data ?? {}) as Partial<ChatState>;
  const chat = d.chat && typeof d.chat === "object" && "id" in d.chat ? d.chat : null;
  return { chat, invites: Array.isArray(d.invites) ? d.invites : [], outgoing: Array.isArray(d.outgoing) ? d.outgoing : [] };
}

function onEvent(view: ChatView, e: ChatEvent): ChatView {
  switch (e.kind) {
    case "invited":
      return view.invites.some(i => i.id === e.invite.id) ? view : { ...view, invites: [...view.invites, e.invite] };
    case "invite_closed":
      return { ...view, invites: view.invites.filter(i => i.id !== e.invite) };
    case "declined":
    case "unanswered": {
      const outgoing = view.outgoing.filter(o => o.id !== e.invite);
      const text = e.kind === "declined" ? `${e.label} declined` : `${e.label} did not answer`;
      return add({ ...view, outgoing }, notice(text));
    }
  }
  // Everything else belongs to one chat: a straggler from a chat this page has left is not news.
  if (!view.room || e.chat !== view.room.id) return view;
  const room = "participants" in e ? { ...view.room, participants: e.participants } : view.room;
  const next = { ...view, room };
  switch (e.kind) {
    case "roster":
      return next;
    case "said": {
      if (view.entries.some(x => x.type === "said" && x.id === e.id)) return next;
      const mine = e.who.id === view.room.me.id;
      const said = add(next, { type: "said", id: e.id, who: e.who, text: e.text, at: e.at, mine });
      return mine ? said : { ...said, heard: view.heard + 1 };
    }
    case "joined":
      // This page's own join is told when the server answers it, so it never waits on the stream.
      if (e.who.id === view.room.me.id) return next;
      return add({ ...next, outgoing: view.outgoing.filter(o => o.machine !== e.who.machine) }, notice(`${e.who.name} joined`));
    case "left":
      return add(next, notice(`${e.who.name} left`));
    case "idle":
    case "back":
      // Your own idling is news to the others, not to you.
      if (e.who.id === view.room.me.id) return next;
      return add(next, notice(e.kind === "idle" ? `${e.who.name} is idle` : `${e.who.name} is back`));
  }
}

function reduce(view: ChatView, action: Action): ChatView {
  switch (action.type) {
    case "loaded": {
      const { chat, invites, outgoing } = action.state;
      const room = chat ? { id: chat.id, me: chat.me, participants: chat.participants } : null;
      // A reload or a reconnect: what was said is gone (D2), but a chat already showing keeps its lines.
      const entries = room && room.id === view.room?.id ? view.entries : [];
      return { ...view, room, entries, invites, outgoing };
    }
    case "event":
      return onEvent(view, action.event);
    case "entered": {
      const { state, chat, me } = action;
      const room = state.chat?.id === chat ? state.chat : { id: chat, me, participants: [me] };
      return { ...view, room, entries: [notice("You joined")], invites: state.invites, outgoing: state.outgoing, entered: view.entered + 1 };
    }
    case "left":
      return { ...view, room: null, entries: [], outgoing: [] };
    case "said": {
      const { said } = action;
      if (!view.room || view.entries.some(x => x.type === "said" && x.id === said.id)) return view;
      return add(view, { type: "said", id: said.id, who: said.who, text: said.text, at: said.at, mine: true });
    }
    case "invited":
      return add({ ...view, outgoing: [...view.outgoing, action.outgoing] }, notice(`You invited ${action.outgoing.label}`));
    case "notice":
      return add(view, notice(action.text));
    case "drop-invite":
      return { ...view, invites: view.invites.filter(i => i.id !== action.id) };
  }
}

export interface Chat extends ChatView {
  page: string;
  /** Starts a chat and invites `machine` to it. */
  start(machine: string, label: string, name: string): Promise<void>;
  invite(machine: string, label: string): Promise<void>;
  accept(invite: ChatInvite, name: string): Promise<void>;
  decline(invite: ChatInvite): Promise<void>;
  leave(): Promise<void>;
  say(text: string): Promise<void>;
  /** Typing, sending, clicking or focusing in the chat: resets the idle clock, and says "back" if it had run out. */
  touch(): void;
  /** Adds a notice of this page's own to the conversation: an invite or a leave that failed, and why. */
  note(text: string): void;
}

/** Keeps the chat for one page. `enabled` is false under `?fixture`, where nothing is connected to chat with. */
export function useChat(enabled = true): Chat {
  const page = useRef(pageId()).current;
  const [view, dispatch] = useReducer(reduce, EMPTY);
  const idle = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const inChat = view.room !== null;

  // Events that arrive while a read of the chat is in flight wait for it, then apply on top: the read may predate
  // them (an invite closed meanwhile must stay closed), and dropping them would lose what only the stream carries.
  const reading = useRef<ChatEvent[] | null>(null);

  const load = useCallback(() => {
    if (reading.current) return;
    reading.current = [];
    const settle = (state: ChatState | null) => {
      const held = reading.current ?? [];
      reading.current = null;
      if (state) dispatch({ type: "loaded", state });
      held.forEach(event => dispatch({ type: "event", event }));
    };
    fetchChat(page).then(
      state => settle(asState(state)),
      // No chat server (an older one, or none yet): the page has no chat, and the menus say so by their errors.
      () => settle(null),
    );
  }, [page]);

  useEffect(() => {
    if (!enabled) return;
    const stop = chatBus.listen({
      event: event => (reading.current ? reading.current.push(event) : dispatch({ type: "event", event })),
      opened: load,
    });
    if (chatBus.isOpen) load();
    return stop;
  }, [enabled, load]);

  const presence = useCallback(
    (to: boolean) => {
      idle.current = to;
      void postChat("presence", { page, idle: to }).catch(() => {});
    },
    [page],
  );

  const arm = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => presence(true), IDLE_AFTER_MS);
  }, [presence]);

  const touch = useCallback(() => {
    if (!inChat) return;
    if (idle.current) presence(false);
    arm();
  }, [inChat, presence, arm]);

  // The clock runs while the page is in a chat, and stops with it.
  useEffect(() => {
    if (!inChat) return;
    idle.current = false;
    arm();
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, [inChat, arm]);

  const enter = useCallback(
    async (chat: string, name: string) => {
      keepName(name);
      const state = asState(await fetchChat(page));
      dispatch({ type: "entered", state, chat, me: { id: page, name, machine: "", label: "", idle: false } });
    },
    [page],
  );

  const start = useCallback(
    async (machine: string, label: string, name: string) => {
      const answer = await postChat<{ chat: string; invite: string }>("start", { page, name, machine });
      await enter(answer.chat, name);
      dispatch({ type: "invited", outgoing: { id: answer.invite, machine, label } });
    },
    [page, enter],
  );

  const invite = useCallback(
    async (machine: string, label: string) => {
      const sent = await postChat<ChatOutgoing>("invite", { page, machine });
      dispatch({ type: "invited", outgoing: { ...sent, label: sent.label || label } });
    },
    [page],
  );

  const accept = useCallback(
    async (inv: ChatInvite, name: string) => {
      try {
        const answer = await postChat<{ chat: string }>("accept", { page, invite: inv.id, name });
        await enter(answer.chat, name);
      } finally {
        dispatch({ type: "drop-invite", id: inv.id });
      }
    },
    [page, enter],
  );

  const decline = useCallback(
    async (inv: ChatInvite) => {
      dispatch({ type: "drop-invite", id: inv.id });
      await postChat("decline", { page, invite: inv.id }).catch(() => {
        // Already answered elsewhere: the modal is closed either way.
      });
    },
    [page],
  );

  const leave = useCallback(async () => {
    await postChat("leave", { page });
    dispatch({ type: "left" });
  }, [page]);

  const say = useCallback(
    async (text: string) => {
      const said = await postChat<ChatSaid>("say", { page, id: ulid(), text });
      dispatch({ type: "said", said });
      touch();
    },
    [page, touch],
  );

  const note = useCallback((text: string) => dispatch({ type: "notice", text }), []);

  return { ...view, page, start, invite, accept, decline, leave, say, touch, note };
}
