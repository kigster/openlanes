import { QueryClientProvider, type QueryClient } from "@tanstack/react-query";
import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { axe } from "vitest-axe";
import { resetSession } from "../api/client";
import { withTurn } from "../api/copilot";
import fixtureLog from "../api/fixtures/copilot.json";
import { COPILOT_KEY, createQueryClient } from "../api/queryClient";
import type { CopilotLog, CopilotTurn } from "../api/types";
import { AskStore } from "../panels/asks";
import { AsksProvider } from "../panels/AsksProvider";
import { AnnouncerProvider } from "../panels/feedback";
import { recorder, snapshot } from "../panels/testing";
import { Copilot } from "./Copilot";
import { ANSWER_TIMEOUT_MS, FIXTURE_REPLY } from "./useCopilot";

const log = fixtureLog as CopilotLog;
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const session = { csrf: "tok-1", node: {}, repo: "github.com/example-org/example-repo" };

let fetchMock: ReturnType<typeof vi.fn>;
let history: CopilotLog;
let posted: Array<{ id: string; text: string }>;
let postAnswer: (body: { id: string; text: string }) => Response;

beforeEach(() => {
  resetSession();
  localStorage.clear();
  history = log;
  posted = [];
  postAnswer = body => json(202, { id: body.id, from: "you", kind: "text", text: body.text, at: "2026-10-13T09:05:00Z", usage: null });
  fetchMock = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === "/api/session") return json(200, session);
    if (path === "/api/copilot" && init?.method === "POST") {
      const body = JSON.parse(String(init.body)) as { id: string; text: string };
      posted.push(body);
      return postAnswer(body);
    }
    if (path === "/api/copilot") return json(200, history);
    return json(404, {});
  });
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
  window.history.replaceState(null, "", "/");
});

function setup({ open = true, store = new AskStore() }: { open?: boolean; store?: AskStore } = {}) {
  if (open) localStorage.setItem("openlanes-copilot-open", "1");
  const client: QueryClient = createQueryClient();
  client.setDefaultOptions({ queries: { retry: false } });
  const { sent, onCommand } = recorder("accepted");
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>
      <AsksProvider store={store}>
        <AnnouncerProvider>{children}</AnnouncerProvider>
      </AsksProvider>
    </QueryClientProvider>
  );
  const view = render(<Copilot onCommand={onCommand} models={snapshot.models} />, { wrapper });
  // As useBoard applies an `event: copilot`. TanStack notifies on a later tick, so the act waits for it.
  const stream = (turn: CopilotTurn) =>
    act(async () => {
      client.setQueryData<CopilotLog>(COPILOT_KEY, old => withTurn(old!, turn));
      await new Promise(resolve => setTimeout(resolve, 0));
    });
  return { ...view, client, sent, onCommand, store, stream };
}

const reply = (id: string, text = "c3po-operator is not built yet, so nobody is listening here."): CopilotTurn => ({
  id, from: "copilot", kind: "text", text, at: "2026-10-13T09:06:00Z", usage: null,
});
const chat = () => screen.getByRole("log", { name: "Conversation with c3po-operator" });

it("draws the conversation from GET /api/copilot, with the model and tokens in its header, accessibly", async () => {
  const { container } = setup();
  expect(await within(chat()).findByText("Why has 001 not moved?")).toBeInTheDocument();
  expect(screen.getByRole("dialog", { name: "c3po-operator" })).toHaveAttribute("data-dock", "right");
  const model = snapshot.models.find(m => m.id === "claude-haiku-4-5")?.label ?? "claude-haiku-4-5";
  expect(screen.getByText(`Copilot for this run. ${model}, ↑ 13.1k ↓ 530`)).toBeInTheDocument();
  expect(within(chat()).getAllByText("You")).toHaveLength(3);
  expect(await axe(container)).toHaveNoViolations();
});

it("says what it is for, and that it is not running, before anything was said", async () => {
  history = { turns: [], usage: { model: null, up: 0, down: 0 } };
  setup();
  expect(await screen.findByText(/Ask c3po-operator about the run/)).toBeInTheDocument();
  expect(screen.getByText("Copilot for this run. Not running, ↑ 0 ↓ 0")).toBeInTheDocument();
});

it("starts minimised to its tab on the right edge, and remembers being opened", async () => {
  const user = userEvent.setup();
  setup({ open: false });
  expect(screen.queryByRole("dialog")).toBeNull();
  await user.click(screen.getByRole("button", { name: "Copilot" }));
  expect(screen.getByRole("textbox", { name: "Message c3po-operator" })).toHaveFocus();
  expect(localStorage.getItem("openlanes-copilot-open")).toBe("1");
  await user.keyboard("{Escape}");
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(localStorage.getItem("openlanes-copilot-open")).toBe("");
});

it("sends a message, shows it at once, reads until the answer arrives, and draws the stream's copy once", async () => {
  const user = userEvent.setup();
  history = { turns: [], usage: { model: null, up: 0, down: 0 } };
  const { stream } = setup();
  const box = await screen.findByRole("textbox", { name: "Message c3po-operator" });
  await user.type(box, "  What costs most?  ");
  await user.click(screen.getByRole("button", { name: "Send" }));
  expect(await within(chat()).findByText("What costs most?")).toBeInTheDocument();
  expect(posted).toEqual([{ id: expect.any(String), text: "What costs most?" }]);
  expect(fetchMock).toHaveBeenCalledWith("/api/copilot", expect.objectContaining({ headers: expect.objectContaining({ "X-CSRF-Token": "tok-1" }) }));
  expect(box).toHaveValue("");
  expect(screen.getByText("Reading the board…")).toBeInTheDocument();
  const id = posted[0].id;
  await stream({ id, from: "you", kind: "text", text: "What costs most?", at: "2026-10-13T09:05:00Z", usage: null });
  await stream(reply(`${id}.1`));
  expect(within(chat()).getAllByText("What costs most?")).toHaveLength(1);
  expect(screen.getByText(/nobody is listening here/)).toBeInTheDocument();
  expect(screen.queryByText("Reading the board…")).toBeNull();
});

it("sends with ⌘ Enter or Ctrl Enter, and does nothing for an empty box", async () => {
  const user = userEvent.setup();
  setup();
  const box = await screen.findByRole("textbox", { name: "Message c3po-operator" });
  await user.click(screen.getByRole("button", { name: "Send" }));
  expect(posted).toHaveLength(0);
  expect(box).toHaveFocus();
  await user.type(box, "Summarise{Control>}{Enter}{/Control}");
  await waitFor(() => expect(posted.map(p => p.text)).toEqual(["Summarise"]));
  await user.type(box, "plain enter{Enter}");
  expect(posted).toHaveLength(1);
});

it("keeps the message and says why when the server refuses it", async () => {
  const user = userEvent.setup();
  postAnswer = () => json(422, { error: "a message is at most 4000 characters" });
  setup();
  const box = await screen.findByRole("textbox", { name: "Message c3po-operator" });
  await user.type(box, "too long");
  await user.click(screen.getByRole("button", { name: "Send" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Not sent: a message is at most 4000 characters");
  expect(box).toHaveValue("too long");
});

it("says the status when a refusal carries no reason", async () => {
  const user = userEvent.setup();
  postAnswer = () => new Response("", { status: 500 });
  setup();
  await user.type(await screen.findByRole("textbox", { name: "Message c3po-operator" }), "hi");
  await user.click(screen.getByRole("button", { name: "Send" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Not sent: POST /api/copilot answered 500");
});

it("stops reading after a minute without an answer", async () => {
  history = { turns: [], usage: { model: null, up: 0, down: 0 } };
  vi.useFakeTimers({ shouldAdvanceTime: true });
  const user = userEvent.setup({ advanceTimers: ms => vi.advanceTimersByTime(ms) });
  setup();
  await user.type(await screen.findByRole("textbox", { name: "Message c3po-operator" }), "hello");
  await user.click(screen.getByRole("button", { name: "Send" }));
  expect(await screen.findByText("Reading the board…")).toBeInTheDocument();
  act(() => void vi.advanceTimersByTime(ANSWER_TIMEOUT_MS));
  expect(screen.queryByText("Reading the board…")).toBeNull();
});

it("puts a dot on its tab for a reply that arrives while it is minimised, and clears it on opening", async () => {
  const user = userEvent.setup();
  const { stream } = setup({ open: false });
  await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/copilot", expect.anything()));
  // What the first load brought was said before this visit: no dot for it.
  await waitFor(() => expect(screen.getByRole("button", { name: "Copilot" })).toBeInTheDocument());
  await stream(reply("01JLATER.1", "Plan 002 just moved to Review."));
  const tab = screen.getByRole("button", { name: "Copilot , new reply" });
  await user.click(tab);
  await user.keyboard("{Escape}");
  expect(screen.getByRole("button", { name: "Copilot" })).toBeInTheDocument();
});

it("draws a confirm card in red and sends its command only when pressed", async () => {
  const user = userEvent.setup();
  const { sent } = setup();
  const button = await screen.findByRole("button", { name: "Stop hansolo-reviewer" });
  expect(button.closest(".cp-card")).toHaveClass("is-confirm");
  expect(sent).toHaveLength(0);
  await user.click(button);
  expect(sent).toEqual([{ kind: "stop", plan: "005.00", agent: "hansolo-reviewer", payload: {} }]);
  expect(await within(chat()).findByText(/Asked hansolo-reviewer on 005 to stop/)).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Stop hansolo-reviewer" })).toBeNull();
});

it("leaves things as they are on Not now", async () => {
  const user = userEvent.setup();
  const { sent } = setup();
  await user.click(await screen.findByRole("button", { name: "Not now" }));
  expect(within(chat()).getByText("Left as it is.")).toBeInTheDocument();
  expect(sent).toHaveLength(0);
});

it("says so in place when the engine refuses a confirmed command", async () => {
  const user = userEvent.setup();
  const client = createQueryClient();
  client.setQueryData(COPILOT_KEY, log);
  const { onCommand } = recorder("refused", "hansolo-reviewer is not running");
  render(
    <QueryClientProvider client={client}>
      <AnnouncerProvider>
        <Copilot onCommand={onCommand} />
      </AnnouncerProvider>
    </QueryClientProvider>,
  );
  await user.click(screen.getByRole("button", { name: "Copilot" }));
  await user.click(screen.getByRole("button", { name: "Stop hansolo-reviewer" }));
  const note = await within(chat()).findByText("Refused: hansolo-reviewer is not running.");
  expect(note).toHaveClass("is-refused");
  // With no models to name it by, the header shows the model's id.
  expect(screen.getByText(/Copilot for this run\. claude-haiku-4-5,/)).toBeInTheDocument();
});

it("puts a drafted answer in the question's answer box without sending anything", async () => {
  const user = userEvent.setup();
  const store = new AskStore();
  const { sent } = setup({ store });
  const draft = "Use the checkout's absolute path, hashed, and keep the path beside it for display.";
  expect(await within(chat()).findByText(draft)).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "Put it in the answer box" }));
  expect(store.get("001.00/B1")).toMatchObject({ draft, inWords: true });
  expect(within(chat()).getByText(/It is in the answer box under Needs you/)).toBeInTheDocument();
  expect(sent).toHaveLength(0);
});

it("answers locally under ?fixture, where nothing is connected", async () => {
  window.history.replaceState(null, "", "/?fixture");
  const user = userEvent.setup();
  setup();
  expect(await screen.findByText(/Ask c3po-operator about the run/)).toBeInTheDocument();
  await user.type(screen.getByRole("textbox", { name: "Message c3po-operator" }), "hello");
  await user.click(screen.getByRole("button", { name: "Send" }));
  expect(await screen.findByText(FIXTURE_REPLY)).toBeInTheDocument();
  expect(fetchMock).not.toHaveBeenCalled();
});

it("survives a private window, where storage throws", async () => {
  const user = userEvent.setup();
  vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
    throw new Error("denied");
  });
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new Error("denied");
  });
  setup({ open: false });
  await user.click(screen.getByRole("button", { name: "Copilot" }));
  expect(screen.getByRole("dialog", { name: "c3po-operator" })).toBeInTheDocument();
  vi.restoreAllMocks();
});
