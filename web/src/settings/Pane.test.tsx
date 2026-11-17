import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { Pane } from "./Pane";
import { errorsByPath, type PaneModel } from "./model";

const pane: PaneModel = {
  id: "merge",
  title: "Merge",
  path: ["merge"],
  fields: [{ path: ["merge", "by"], node: { type: "string", description: "Who" }, label: "By" }],
  children: [{ id: "c", title: "Child", path: ["merge", "c"], fields: [{ path: ["merge", "c", "x"], node: { type: "string" }, label: "X" }], children: [] }],
};

/** The page's side of the pane: which ids are open. */
function Harness({ onChange, errors }: { onChange: (path: string[], value: unknown) => void; errors: ReturnType<typeof errorsByPath> }) {
  const [ids, setIds] = useState<ReadonlySet<string>>(new Set());
  const toggle = (id: string, open: boolean) => setIds(s => (open ? new Set([...s, id]) : new Set([...s].filter(x => x !== id))));
  return <Pane pane={pane} values={{ merge: { by: "human" } }} defaults={{}} errors={errors} onChange={onChange} openIds={ids} onToggle={toggle} />;
}

const draw = (onChange = vi.fn(), errors = errorsByPath([])) => render(<Harness onChange={onChange} errors={errors} />);
const openAll = async () => {
  await userEvent.click(screen.getByRole("button", { name: "Open Merge" }));
  await userEvent.click(screen.getByRole("button", { name: "Open Child" }));
};

it("is folded on load, with its title as a heading and an anchor the nav can scroll to", () => {
  const { container } = draw();
  expect(screen.getByRole("heading", { level: 2, name: /Merge/ })).toBeInTheDocument();
  expect(screen.queryByLabelText("By")).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Open Merge" })).toHaveTextContent("+");
  expect(container.querySelector("#set-pane-merge")).not.toBeNull();
});

it("opens and folds with the −/+ button, showing fields under their labels and sub-panes as h2", async () => {
  draw();
  await openAll();
  expect(screen.getByLabelText("By")).toHaveValue("human");
  expect(screen.getByLabelText("By")).toHaveAttribute("name", "merge.by");
  expect(screen.getByLabelText("X")).toBeInTheDocument();
  expect(screen.getAllByRole("heading", { level: 2 })).toHaveLength(2);
  await userEvent.click(screen.getByRole("button", { name: "Collapse Merge" }));
  expect(screen.queryByLabelText("By")).not.toBeInTheDocument();
});

it("shows a field's error once its pane is open", async () => {
  draw(vi.fn(), errorsByPath([{ path: ["merge", "c", "x"], message: "bad" }]));
  await openAll();
  expect(screen.getByRole("alert")).toHaveTextContent("bad");
});

it("reports an edit with its path", async () => {
  const change = vi.fn();
  draw(change);
  await openAll();
  await userEvent.type(screen.getByLabelText("By"), "!");
  expect(change).toHaveBeenLastCalledWith(["merge", "by"], "human!");
});
