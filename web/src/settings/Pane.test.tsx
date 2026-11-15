import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Pane } from "./Pane";
import { errorsByPath, type PaneModel } from "./model";

const pane: PaneModel = {
  id: "merge",
  title: "merge",
  path: ["merge"],
  fields: [{ path: ["merge", "by"], node: { type: "string", description: "Who" } }],
  children: [{ id: "c", title: "child", path: ["merge", "c"], fields: [{ path: ["merge", "c", "x"], node: { type: "string" } }], children: [] }],
};

const draw = (onChange = vi.fn()) =>
  render(<Pane pane={pane} values={{ merge: { by: "human" } }} defaults={{}} errors={errorsByPath([{ path: ["merge", "by"], message: "bad" }])} onChange={onChange} />);

it("is open on load and shows its fields, sub-panes and field errors", () => {
  draw();
  expect(screen.getByLabelText("merge.by")).toHaveValue("human");
  expect(screen.getByLabelText("merge.c.x")).toBeInTheDocument();
  expect(screen.getByRole("alert")).toHaveTextContent("bad");
  expect(screen.getByRole("button", { name: "Collapse merge" })).toHaveTextContent("−");
});

it("folds and opens with the −/+ button", async () => {
  draw();
  await userEvent.click(screen.getByRole("button", { name: "Collapse merge" }));
  expect(screen.queryByLabelText("merge.by")).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Open merge" })).toHaveTextContent("+");
  await userEvent.click(screen.getByRole("button", { name: "Open merge" }));
  expect(screen.getByLabelText("merge.by")).toBeInTheDocument();
});

it("reports an edit with its path", async () => {
  const change = vi.fn();
  draw(change);
  await userEvent.type(screen.getByLabelText("merge.by"), "!");
  expect(change).toHaveBeenLastCalledWith(["merge", "by"], "human!");
});
