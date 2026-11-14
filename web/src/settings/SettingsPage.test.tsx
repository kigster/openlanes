import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { resetSession } from "../api/client";
import { SettingsPage } from "./SettingsPage";
import { doc } from "./fixture";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
let fetchMock: ReturnType<typeof vi.fn>;
const puts = () => fetchMock.mock.calls.filter(([, init]) => init?.method === "PUT");

const answer = (put?: () => Response) =>
  fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
    if (url === "/api/session") return json({ csrf: "tok", node: {}, repo: "r" });
    if (init?.method === "PUT") return put!();
    return json(doc);
  });

const draw = () =>
  render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <SettingsPage />
    </QueryClientProvider>,
  );

beforeEach(() => {
  resetSession();
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

it("lists every schema key with each pane open, and the save button with its note", async () => {
  answer();
  draw();
  await screen.findByRole("heading", { name: "Project settings" });
  for (const key of ["project", "frontend", "jobs", "ratio", "tags", "merge.by", "merge.nested.depth", "commands.run.fast"]) expect(screen.getByLabelText(key)).toBeInTheDocument();
  expect(screen.getAllByRole("button", { name: /^Collapse / }).map(b => b.getAttribute("aria-label"))).toEqual(["Collapse General", "Collapse merge", "Collapse commands", "Collapse run", "Collapse api docs"]);
  expect(screen.getByLabelText("project")).toHaveValue("demo");
  expect(screen.getByLabelText("jobs")).toHaveAttribute("placeholder", "4");
  expect(screen.getByRole("button", { name: "Save, commit and push to main" })).toBeInTheDocument();
  expect(screen.getByText(/commits it alone and pushes main/)).toBeInTheDocument();
});

it("collapses a pane", async () => {
  answer();
  draw();
  await screen.findByLabelText("project");
  await userEvent.click(screen.getByRole("button", { name: "Collapse General" }));
  expect(screen.queryByLabelText("project")).not.toBeInTheDocument();
});

it("sends nothing when nothing changed", async () => {
  answer();
  draw();
  await screen.findByLabelText("project");
  await userEvent.click(screen.getByRole("button", { name: "Save, commit and push to main" }));
  expect(screen.getByRole("status")).toHaveTextContent("Nothing changed");
  expect(puts()).toHaveLength(0);
});

it("sends the pruned values with the etag, and shows the commit", async () => {
  answer(() => json({ changed: true, commit: "abcdef0123", etag: "e2" }));
  draw();
  await userEvent.clear(await screen.findByLabelText("jobs"));
  await userEvent.type(screen.getByLabelText("jobs"), "6");
  await userEvent.click(screen.getByRole("button", { name: "Save, commit and push to main" }));
  await screen.findByText(/Saved and pushed to main as abcdef0/);
  const [, init] = puts()[0];
  expect((init as RequestInit).headers).toMatchObject({ "If-Match": "e1" });
  expect(JSON.parse((init as RequestInit).body as string).values).toEqual({ project: "demo", jobs: 6, merge: { by: "human" } });
});

it("reports a server-side no-change", async () => {
  answer(() => json({ changed: false }));
  draw();
  await userEvent.type(await screen.findByLabelText("project"), "x");
  await userEvent.click(screen.getByRole("button", { name: "Save, commit and push to main" }));
  await screen.findByText("Nothing changed, so nothing was written.");
});

it("shows a 422 on its field, and an error with no field in a list", async () => {
  answer(() => json({ errors: [{ path: ["jobs"], message: "must be >= 1" }, { path: ["mystery"], message: "odd" }] }, 422));
  draw();
  await userEvent.type(await screen.findByLabelText("project"), "x");
  await userEvent.click(screen.getByRole("button", { name: "Save, commit and push to main" }));
  await waitFor(() => expect(screen.getByText("must be >= 1")).toBeInTheDocument());
  expect(screen.getByText("mystery: odd")).toBeInTheDocument();
});

it("shows a 409 reason beside the button", async () => {
  answer(() => json({ refusal: "dirty_config", reason: ".openlanes.yml has uncommitted edits" }, 409));
  draw();
  await userEvent.type(await screen.findByLabelText("project"), "x");
  await userEvent.click(screen.getByRole("button", { name: "Save, commit and push to main" }));
  expect(await screen.findByText(".openlanes.yml has uncommitted edits")).toBeInTheDocument();
});

it("shows any other failure's message", async () => {
  answer(() => json({}, 500));
  draw();
  await userEvent.type(await screen.findByLabelText("project"), "x");
  await userEvent.click(screen.getByRole("button", { name: "Save, commit and push to main" }));
  expect(await screen.findByText("PUT /api/settings answered 500")).toBeInTheDocument();
});

it("says so when the settings cannot be loaded", async () => {
  fetchMock.mockResolvedValue(json({}, 500));
  draw();
  expect(await screen.findByRole("alert")).toHaveTextContent("Could not load the settings");
});

it("keeps the saved note when the refetch brings a new etag and remounts the form", async () => {
  let saved = false;
  fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
    if (url === "/api/session") return json({ csrf: "tok", node: {}, repo: "r" });
    if (init?.method === "PUT") {
      saved = true;
      return json({ changed: true, commit: "abcdef0123", etag: "e2" });
    }
    return json(saved ? { ...doc, etag: "e2", values: { ...doc.values, project: "demox" } } : doc);
  });
  draw();
  await userEvent.type(await screen.findByLabelText("project"), "x");
  await userEvent.click(screen.getByRole("button", { name: "Save, commit and push to main" }));
  await waitFor(() => expect(screen.getByLabelText("project")).toHaveValue("demox"));
  expect(screen.getByRole("status")).toHaveTextContent("Saved and pushed to main as abcdef0");
});
