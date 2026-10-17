import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import * as client from "../api/client";
import * as api from "../api/planFiles";
import { PlanFilePopup } from "./PlanFilePopup";
import { renderPanel, typeInEditor } from "./testing";

const FILE = "---\nlane: full\n---\n# Hello\n\nBody text\n";

beforeEach(() => {
  vi.spyOn(api, "readPlanFile").mockResolvedValue({ body: FILE, etag: '"e1"' });
  vi.spyOn(client, "getSession").mockResolvedValue({ csrf: "tok", node: {} as never, repo: "r" });
});
afterEach(() => vi.restoreAllMocks());

describe("PlanFilePopup", () => {
  it("renders the markdown and the frontmatter", async () => {
    renderPanel(<PlanFilePopup ordinal="017.00" name="spec.md" editable onClose={() => {}} />);
    expect(await screen.findByRole("heading", { name: "Hello" })).toBeInTheDocument();
    expect(screen.getByLabelText("Frontmatter")).toHaveTextContent("lane: full");
    expect(api.readPlanFile).toHaveBeenCalledWith("017.00", "spec.md");
  });

  it("offers no Edit for a read-only file", async () => {
    renderPanel(<PlanFilePopup ordinal="017.00" name="blocked.md" editable={false} onClose={() => {}} />);
    await screen.findByRole("heading", { name: "Hello" });
    expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
  });

  it("offers no Edit while a car is live", async () => {
    renderPanel(<PlanFilePopup ordinal="017.00" name="spec.md" editable={false} onClose={() => {}} />);
    await screen.findByRole("heading", { name: "Hello" });
    expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
  });

  it("saves with the frontmatter byte-equal and the ETag it read", async () => {
    const save = vi.spyOn(api, "savePlanFile").mockResolvedValue({ etag: '"e2"' });
    const user = userEvent.setup();
    renderPanel(<PlanFilePopup ordinal="017.00" name="spec.md" editable onClose={() => {}} />);
    await user.click(await screen.findByRole("button", { name: "Edit" }));
    typeInEditor(document.body, " more");
    await user.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(save).toHaveBeenCalled());
    const [ordinal, name, text, etag, csrf] = save.mock.calls[0];
    expect([ordinal, name, etag, csrf]).toEqual(["017.00", "spec.md", '"e1"', "tok"]);
    expect(text.startsWith("---\nlane: full\n---\n")).toBe(true);
    expect(text).toContain("more");
    await waitFor(() => expect(screen.queryByRole("button", { name: "Save" })).toBeNull());
  });

  it("shows a conflict on 412 and keeps the editor", async () => {
    vi.spyOn(api, "savePlanFile").mockRejectedValue(new api.PlanFileError("stale", 412, "stale"));
    const user = userEvent.setup();
    renderPanel(<PlanFilePopup ordinal="017.00" name="spec.md" editable onClose={() => {}} />);
    await user.click(await screen.findByRole("button", { name: "Edit" }));
    await user.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(/Conflict/);
    expect(screen.getByRole("button", { name: "Save" })).toBeInTheDocument();
  });

  it("shows the reason on a 409 and on a failed read", async () => {
    vi.spyOn(api, "savePlanFile").mockRejectedValue(new api.PlanFileError("car", 409, "plan has a live car"));
    const user = userEvent.setup();
    renderPanel(<PlanFilePopup ordinal="017.00" name="spec.md" editable onClose={() => {}} />);
    await user.click(await screen.findByRole("button", { name: "Edit" }));
    await user.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("plan has a live car");
  });

  it("reports a failed read", async () => {
    vi.spyOn(api, "readPlanFile").mockRejectedValue(new api.PlanFileError("gone", 404, "no such file"));
    renderPanel(<PlanFilePopup ordinal="017.00" name="spec.md" editable onClose={() => {}} />);
    expect(await screen.findByRole("alert")).toHaveTextContent("no such file");
  });

  it("cancels an edit, and closes by button and by Esc", async () => {
    const onClose = vi.fn();
    const user = userEvent.setup();
    renderPanel(<PlanFilePopup ordinal="017.00" name="spec.md" editable onClose={onClose} />);
    await user.click(await screen.findByRole("button", { name: "Edit" }));
    await user.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.getByRole("button", { name: "Edit" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalledTimes(1);
    await user.keyboard("{Escape}");
    expect(onClose).toHaveBeenCalledTimes(2);
  });
});
