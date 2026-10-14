import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { axe } from "vitest-axe";
import { resetSession } from "../api/client";
import type { ChatEvent, ChatInvite, ChatParticipant, ChatState } from "../api/types";
import { chatBus } from "./bus";
import { ChatRoom } from "./ChatRoom";
import { menuItems } from "./context";
import { linkify } from "./linkify";
import { MachineMenu } from "./MachineMenu";
import { eventsUrl, pageId } from "./page";
import { IDLE_AFTER_MS, LIMIT } from "./useChat";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const session = { csrf: "tok-1", node: {}, repo: "github.com/example-org/example-repo" };
const SAM = { id: "77aa0c7be21d44a8f6031c99", user: "sam", host: "ci-runner-2" };
const CHAT = "0b6c2a1e-1111-4222-8333-944445555666";

const person = (over: Partial<ChatParticipant> = {}): ChatParticipant => ({
  id: "page-them-0001",
  name: "Sam",
  machine: SAM.id,
  label: "sam@ci-runner-2",
  idle: false,
  ...over,
});

let state: ChatState;
let posts: Array<{ action: string; body: Record<string, unknown> }>;
let answer: (action: string, body: Record<string, unknown>) => Response;

function me(name = "Dana"): ChatParticipant {
  return { id: pageId(), name, machine: "3f9a0c7be21d44a8f6031c5d", label: "dana@studio", idle: false };
}

beforeEach(() => {
  resetSession();
  localStorage.clear();
  sessionStorage.clear();
  chatBus.opened(); // the stream's chat_cursor, which the page waits for before it reads the chat
  state = { chat: null, invites: [], outgoing: [] };
  posts = [];
  answer = (action, body) => {
    if (action === "start") {
      state = { chat: { id: CHAT, me: me(String(body.name)), participants: [me(String(body.name))] }, invites: [], outgoing: [] };
      return json(202, { chat: CHAT, invite: "inv-1" });
    }
    if (action === "accept") {
      state = { chat: { id: CHAT, me: me(String(body.name)), participants: [person(), me(String(body.name))] }, invites: [], outgoing: [] };
      return json(202, { chat: CHAT });
    }
    if (action === "say") return json(202, { id: body.id, text: body.text, at: "2026-10-13T09:00:00Z", who: me() });
    if (action === "invite") return json(202, { id: "inv-2", machine: body.machine, label: "kim@lab" });
    if (action === "leave") state = { chat: null, invites: [], outgoing: [] };
    return json(202, {});
  };
  vi.stubGlobal(
    "fetch",
    vi.fn(async (path: string, init?: RequestInit) => {
      if (path === "/api/session") return json(200, session);
      const action = path.match(/^\/api\/chat\/(\w+)$/)?.[1];
      if (action && init?.method === "POST") {
        const body = JSON.parse(String(init.body)) as Record<string, unknown>;
        posts.push({ action, body });
        return answer(action, body);
      }
      if (path.startsWith("/api/chat?page=")) return json(200, state);
      return json(404, {});
    }),
  );
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

function Harness({ machines = [SAM] }: { machines?: Array<typeof SAM> }) {
  const [open, setOpen] = useState<string | null>(null);
  return (
    <ChatRoom user="dana">
      {machines.map(m => (
        <span key={m.id}>
          <button type="button" onContextMenu={e => (e.preventDefault(), setOpen(m.id))}>
            {m.user}@{m.host}
          </button>
          <MachineMenu node={m} open={open === m.id} onOpenChange={o => setOpen(o ? m.id : null)} />
        </span>
      ))}
    </ChatRoom>
  );
}

const send = (event: ChatEvent) => act(() => chatBus.deliver(event));
const posted = (action: string) => posts.filter(p => p.action === action).map(p => p.body);

async function startChat(name?: string) {
  render(<Harness />);
  await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
  await userEvent.click(await screen.findByRole("menuitem", { name: /Start Chat/ }));
  const input = await screen.findByLabelText("Name");
  if (name !== undefined) {
    await userEvent.clear(input);
    await userEvent.type(input, name);
  }
  await userEvent.keyboard("{Enter}");
  return screen.findByText("You joined");
}

const panel = () => document.getElementById("chat")!;

describe("the machine's menu", () => {
  it("opens on the caret and offers Start Chat outside a chat", async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
    const menu = await screen.findByRole("menu");
    expect(within(menu).getAllByRole("menuitem").map(i => i.textContent)).toEqual(["Start Chatwith sam@ci-runner-2"]);
  });

  it("opens on a right-click on the tab too", async () => {
    render(<Harness />);
    fireEvent.contextMenu(screen.getByRole("button", { name: "sam@ci-runner-2" }));
    expect(await screen.findByRole("menuitem", { name: /Start Chat/ })).toBeInTheDocument();
  });

  it("offers Stop Chat on a machine in the chat, Invite to Chat beside it on one that is not, and waits on an invite", () => {
    const room = { id: CHAT, me: me(), participants: [me(), person()] };
    expect(menuItems({ room: null, outgoing: [] }, SAM)).toEqual(["start"]);
    expect(menuItems({ room, outgoing: [] }, SAM)).toEqual(["stop"]);
    expect(menuItems({ room, outgoing: [] }, { id: "kim" })).toEqual(["invite", "stop"]);
    expect(menuItems({ room, outgoing: [{ id: "i", machine: "kim", label: "kim@lab" }] }, { id: "kim" })).toEqual(["inviting", "stop"]);
  });

  it("draws nothing outside a ChatRoom", () => {
    const { container } = render(<MachineMenu node={SAM} open={false} onOpenChange={() => {}} />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe("the Name dialog", () => {
  it("is prefilled with the machine's user on first use", async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Start Chat/ }));
    expect(await screen.findByLabelText("Name")).toHaveValue("dana");
    expect(await axe(document.body)).toHaveNoViolations();
  });

  it("is prefilled with the name last used, and asked again every time", async () => {
    localStorage.setItem("openlanes-chat-name", "Dee");
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Start Chat/ }));
    expect(await screen.findByLabelText("Name")).toHaveValue("Dee");
  });

  it("refuses an empty name and says why", async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Start Chat/ }));
    await userEvent.clear(await screen.findByLabelText("Name"));
    await userEvent.click(screen.getByRole("button", { name: "Start" }));
    expect(screen.getByRole("alert")).toHaveTextContent("A name is needed");
    expect(posted("start")).toEqual([]);
  });

  it("shows the server's refusal and stays open", async () => {
    answer = () => json(422, { error: "no machine 77aa is on this Redis now" });
    render(<Harness />);
    await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Start Chat/ }));
    await userEvent.click(await screen.findByRole("button", { name: "Start" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("no machine 77aa is on this Redis now");
  });
});

describe("starting a chat", () => {
  it("starts with Enter, remembers the name, and opens the panel docked bottom left", async () => {
    await startChat("Dana");
    expect(posted("start")).toEqual([{ page: pageId(), name: "Dana", machine: SAM.id }]);
    expect(localStorage.getItem("openlanes-chat-name")).toBe("Dana");
    expect(panel()).toHaveAttribute("data-dock", "left");
    expect(panel()).not.toHaveAttribute("hidden");
    expect(within(panel()).getByRole("heading", { level: 2 })).toHaveTextContent("Dana");
    expect(within(panel()).getByText("You joined")).toBeInTheDocument();
    expect(within(panel()).getByText("You invited sam@ci-runner-2")).toBeInTheDocument();
    expect(await axe(panel())).toHaveNoViolations();
  });

  it("minimises to a tab on the left edge", async () => {
    await startChat();
    await userEvent.click(within(panel()).getByRole("button", { name: "Minimise" }));
    const tab = document.getElementById("chat-tab");
    expect(tab).toHaveAttribute("data-dock", "left");
    expect(tab).toBeVisible();
    expect(panel()).toHaveAttribute("hidden");
  });

  it("lists who is in the chat in the header, and tells of joins, leaves, idling and coming back", async () => {
    await startChat("Dana");
    send({ kind: "joined", chat: CHAT, who: person(), participants: [me(), person()] });
    expect(within(panel()).getByRole("heading", { level: 2 })).toHaveTextContent("Dana, Sam");
    send({ kind: "idle", chat: CHAT, who: person({ idle: true }), participants: [me(), person({ idle: true })] });
    expect(within(panel()).getByRole("heading", { level: 2 })).toHaveTextContent("Dana, Sam (idle)");
    send({ kind: "back", chat: CHAT, who: person(), participants: [me(), person()] });
    send({ kind: "left", chat: CHAT, who: person(), participants: [me()] });
    const notices = [...panel().querySelectorAll(".chat-notice")].map(n => n.textContent);
    expect(notices).toEqual(["You joined", "You invited sam@ci-runner-2", "Sam joined", "Sam is idle", "Sam is back", "Sam left"]);
  });

  it("does not tell you of your own idling, and ignores another chat's news", async () => {
    await startChat("Dana");
    send({ kind: "idle", chat: CHAT, who: me(), participants: [me()] });
    send({ kind: "joined", chat: "another", who: person(), participants: [person()] });
    send({ kind: "roster", chat: CHAT, participants: [me(), person({ name: "Kim" })] });
    expect(panel().querySelectorAll(".chat-notice")).toHaveLength(2);
    expect(within(panel()).getByRole("heading", { level: 2 })).toHaveTextContent("Dana, Kim");
  });

  it("says when the invited machine declined or did not answer", async () => {
    await startChat();
    send({ kind: "unanswered", invite: "inv-1", machine: SAM.id, label: "sam@ci-runner-2" });
    send({ kind: "declined", invite: "inv-9", machine: "kim", label: "kim@lab" });
    expect(within(panel()).getByText("sam@ci-runner-2 did not answer")).toBeInTheDocument();
    expect(within(panel()).getByText("kim@lab declined")).toBeInTheDocument();
  });

  it("invites another machine from its menu, then shows Stop Chat, which leaves", async () => {
    const KIM = { id: "1111aaaa2222bbbb3333cccc", user: "kim", host: "lab" };
    render(<Harness machines={[SAM, KIM]} />);
    await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Start Chat/ }));
    await userEvent.click(await screen.findByRole("button", { name: "Start" }));
    await screen.findByText("You joined");
    await userEvent.click(screen.getByRole("button", { name: "Chat with kim@lab" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Invite to Chat/ }));
    expect(posted("invite")).toEqual([{ page: pageId(), machine: KIM.id }]);
    await userEvent.click(screen.getByRole("button", { name: "Chat with kim@lab" }));
    expect(await screen.findByRole("menuitem", { name: /Waiting for kim@lab/ })).toHaveAttribute("data-disabled");
    await userEvent.click(screen.getByRole("menuitem", { name: /Stop Chat/ }));
    await waitFor(() => expect(document.getElementById("chat")).toBeNull());
    expect(posted("leave")).toEqual([{ page: pageId() }]);
  });

  it("says in the conversation why an invite failed", async () => {
    const KIM = { id: "1111aaaa2222bbbb3333cccc", user: "kim", host: "lab" };
    render(<Harness machines={[SAM, KIM]} />);
    await userEvent.click(screen.getByRole("button", { name: "Chat with sam@ci-runner-2" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Start Chat/ }));
    await userEvent.click(await screen.findByRole("button", { name: "Start" }));
    await screen.findByText("You joined");
    answer = () => json(422, { error: "no machine kim is on this Redis now" });
    await userEvent.click(screen.getByRole("button", { name: "Chat with kim@lab" }));
    await userEvent.click(await screen.findByRole("menuitem", { name: /Invite to Chat/ }));
    expect(await within(panel()).findByText("Could not invite kim@lab: no machine kim is on this Redis now")).toBeInTheDocument();
  });
});

describe("the composer", () => {
  it("sends with Cmd-Enter and shows the message once, links clickable", async () => {
    await startChat("Dana");
    const box = within(panel()).getByLabelText("Message everyone in the chat");
    await userEvent.type(box, "see https://example.com/x.");
    await userEvent.keyboard("{Meta>}{Enter}{/Meta}");
    await waitFor(() => expect(posted("say")).toHaveLength(1));
    const id = String(posted("say")[0].id);
    send({ kind: "said", chat: CHAT, who: me(), id, text: "see https://example.com/x.", at: "2026-10-13T09:00:00Z" });
    const said = await within(panel()).findAllByText(/^see/);
    expect(said).toHaveLength(1);
    expect(within(panel()).getByRole("link", { name: "https://example.com/x" })).toHaveAttribute("href", "https://example.com/x");
    expect(box).toHaveValue("");
  });

  it("sends with Ctrl-Enter and the Send button too", async () => {
    await startChat();
    const box = within(panel()).getByLabelText("Message everyone in the chat");
    await userEvent.type(box, "one");
    await userEvent.keyboard("{Control>}{Enter}{/Control}");
    await waitFor(() => expect(posted("say")).toHaveLength(1));
    await userEvent.type(box, "two");
    await userEvent.click(within(panel()).getByRole("button", { name: "Send" }));
    await waitFor(() => expect(posted("say").map(b => b.text)).toEqual(["one", "two"]));
  });

  it("holds at most 4,000 characters, and says how many over", async () => {
    await startChat();
    const box = within(panel()).getByLabelText("Message everyone in the chat");
    fireEvent.change(box, { target: { value: "x".repeat(LIMIT) } });
    expect(within(panel()).getByText("4,000 / 4,000")).toBeInTheDocument();
    expect(within(panel()).getByRole("button", { name: "Send" })).toBeEnabled();
    fireEvent.change(box, { target: { value: "x".repeat(LIMIT + 2) } });
    expect(within(panel()).getByText("2 characters over the 4,000 limit")).toBeInTheDocument();
    expect(within(panel()).getByRole("button", { name: "Send" })).toBeDisabled();
    await userEvent.keyboard("{Meta>}{Enter}{/Meta}");
    expect(posted("say")).toEqual([]);
  });

  it("shows why a message was not sent", async () => {
    await startChat();
    answer = () => json(422, { error: "a message is at most 4000 characters" });
    await userEvent.type(within(panel()).getByLabelText("Message everyone in the chat"), "hi{Meta>}{Enter}{/Meta}");
    expect(await within(panel()).findByText("Not sent: a message is at most 4000 characters")).toBeInTheDocument();
  });

  it("puts a dot on the tab for a message heard while minimised", async () => {
    await startChat();
    await userEvent.click(within(panel()).getByRole("button", { name: "Minimise" }));
    send({ kind: "said", chat: CHAT, who: person(), id: "m1", text: "ping", at: "2026-10-13T09:00:00Z" });
    expect(document.getElementById("chat-tab")).toHaveTextContent("Chat, new reply");
  });
});

describe("going idle", () => {
  it("tells the others after 60 seconds untouched, and that you are back on the next touch", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    await startChat();
    act(() => {
      vi.advanceTimersByTime(IDLE_AFTER_MS - 1);
    });
    expect(posted("presence")).toEqual([]);
    act(() => {
      vi.advanceTimersByTime(1);
    });
    await waitFor(() => expect(posted("presence")).toEqual([{ page: pageId(), idle: true }]));
    fireEvent.pointerDown(within(panel()).getByRole("heading", { level: 2 }));
    await waitFor(() => expect(posted("presence")).toEqual([{ page: pageId(), idle: true }, { page: pageId(), idle: false }]));
  });

  it("counts a key that changes no text as a touch", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    await startChat();
    act(() => {
      vi.advanceTimersByTime(IDLE_AFTER_MS);
    });
    await waitFor(() => expect(posted("presence")).toEqual([{ page: pageId(), idle: true }]));
    fireEvent.keyDown(within(panel()).getByLabelText("Message everyone in the chat"), { key: "ArrowLeft" });
    await waitFor(() => expect(posted("presence")).toEqual([{ page: pageId(), idle: true }, { page: pageId(), idle: false }]));
  });
});

describe("an invite", () => {
  const invite: ChatInvite = {
    id: "inv-7",
    chat: CHAT,
    from: person(),
    machine: "3f9a0c7be21d44a8f6031c5d",
    label: "dana@studio",
    expires_at: "2026-10-13T09:01:00Z",
  };

  it("shows a modal naming who invited you; Decline closes it", async () => {
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    send({ kind: "invited", invite });
    const modal = await screen.findByRole("dialog", { name: "Invitation to chat" });
    expect(modal).toHaveTextContent("Sam on sam@ci-runner-2 invites you to a chat.");
    expect(await axe(document.body)).toHaveNoViolations();
    await userEvent.click(within(modal).getByRole("button", { name: "Decline" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(posted("decline")).toEqual([{ page: pageId(), invite: "inv-7" }]);
  });

  it("Accept asks for a name, and Join puts you in the chat", async () => {
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    send({ kind: "invited", invite });
    send({ kind: "invited", invite }); // the same invite twice is one modal
    await userEvent.click(await screen.findByRole("button", { name: "Accept" }));
    const name = await screen.findByLabelText("Name");
    expect(name).toHaveValue("dana");
    expect(screen.getByRole("dialog", { name: "Join the chat" })).toHaveTextContent("Sam (sam@ci-runner-2) invited you.");
    await userEvent.click(screen.getByRole("button", { name: "Join" }));
    await waitFor(() => expect(panel()).not.toHaveAttribute("hidden"));
    expect(posted("accept")).toEqual([{ page: pageId(), invite: "inv-7", name: "dana" }]);
    expect(within(panel()).getByRole("heading", { level: 2 })).toHaveTextContent("Sam, dana");
  });

  it("says that accepting leaves the chat you are in", async () => {
    await startChat();
    send({ kind: "invited", invite });
    expect(await screen.findByRole("dialog", { name: "Invitation to chat" })).toHaveTextContent("You are in a chat now: accepting leaves it.");
  });

  it("closes when it is answered on another page or expires", async () => {
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    send({ kind: "invited", invite });
    await screen.findByRole("dialog", { name: "Invitation to chat" });
    send({ kind: "invite_closed", invite: "inv-7", answer: "expired" });
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("tells a Name dialog opened for it that it expired, and Cancel declines", async () => {
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    send({ kind: "invited", invite });
    await userEvent.click(await screen.findByRole("button", { name: "Accept" }));
    await screen.findByLabelText("Name");
    send({ kind: "invite_closed", invite: "inv-7", answer: "accepted" });
    expect(await screen.findByRole("alert")).toHaveTextContent("That invite is no longer open");
    expect(screen.getByRole("button", { name: "Join" })).toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(posted("decline")).toEqual([{ page: pageId(), invite: "inv-7" }]);
  });

  it("picks up the invites already open when the page loads, and its chat, minimised", async () => {
    state = { chat: { id: CHAT, me: me(), participants: [me(), person()] }, invites: [invite], outgoing: [] };
    render(<Harness />);
    expect(await screen.findByRole("dialog", { name: "Invitation to chat" })).toBeInTheDocument();
    expect(panel()).toHaveAttribute("hidden");
    expect(document.getElementById("chat-tab")).toHaveAttribute("data-dock", "left");
  });

  it("asks again for who is in the chat after a reconnect", async () => {
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    state = { chat: { id: CHAT, me: me(), participants: [me()] }, invites: [], outgoing: [] };
    act(() => chatBus.opened());
    await waitFor(() => expect(document.getElementById("chat")).not.toBeNull());
  });
});

describe("reading the chat", () => {
  const invite: ChatInvite = { id: "inv-8", chat: CHAT, from: person(), machine: "m", label: "dana@studio", expires_at: "2026-10-13T09:01:00Z" };

  it("holds events that arrive while the read is in flight, and applies them on top of it", async () => {
    let answerRead: (r: Response) => void = () => {};
    vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>(resolve => (answerRead = resolve))));
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    // The read began before the invite was closed; its answer must not bring the modal back.
    send({ kind: "invite_closed", invite: "inv-8", answer: "declined" });
    await act(async () => answerRead(json(200, { chat: null, invites: [invite], outgoing: [] })));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("reads once per open, so an open during a read does not start a second", async () => {
    const pending = vi.fn(() => new Promise<Response>(() => {}));
    vi.stubGlobal("fetch", pending);
    render(<Harness />);
    await waitFor(() => expect(pending).toHaveBeenCalledTimes(1));
    act(() => chatBus.opened());
    expect(pending).toHaveBeenCalledTimes(1);
  });
});

describe("plumbing", () => {
  it("turns URLs into links and leaves the rest as text", () => {
    const parts = linkify("a http://x.io/b, and <b>no</b> https://y.io");
    expect(parts.filter(p => typeof p === "string")).toEqual(["a ", ", and <b>no</b> "]);
    expect(parts).toHaveLength(4);
    expect(linkify("plain")).toEqual(["plain"]);
  });

  it("keeps the page's id for the session, and puts it on the stream's URL", () => {
    const id = pageId();
    expect(pageId()).toBe(id);
    expect(eventsUrl()).toBe(`/api/events?page=${id}`);
  });

  it("makes do with one id when session storage is refused", () => {
    const get = vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    expect(pageId()).toBe(pageId());
    get.mockRestore();
  });

  it("reads a server without the chat as no chat at all", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(200, { me: null, others: [] })));
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    expect(document.getElementById("chat")).toBeNull();
  });

  it("makes do when the chat cannot be read at all", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => json(500, {})));
    render(<Harness />);
    await waitFor(() => expect(fetch).toHaveBeenCalled());
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("is off under ?fixture", () => {
    render(
      <ChatRoom user="dana" enabled={false}>
        <MachineMenu node={SAM} open onOpenChange={() => {}} />
      </ChatRoom>,
    );
    expect(screen.queryByRole("button", { name: /Chat with/ })).toBeNull();
  });
});
