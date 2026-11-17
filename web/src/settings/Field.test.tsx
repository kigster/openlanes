import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Field } from "./Field";

const draw = (node: object, value: unknown, extra: Partial<Parameters<typeof Field>[0]> = {}) => {
  const onChange = vi.fn();
  render(<Field path={["a", "b"]} label="A B" node={node} value={value} fallback={undefined} onChange={onChange} {...extra} />);
  return onChange;
};

it("renders text with its label and help line, and sends null when emptied", async () => {
  const change = draw({ type: ["string", "null"], description: "Help me" }, "x");
  expect(screen.getByLabelText("A B")).toHaveValue("x");
  expect(screen.getByText("Help me")).toBeInTheDocument();
  await userEvent.clear(screen.getByLabelText("A B"));
  expect(change).toHaveBeenLastCalledWith(null);
  fireEvent.change(screen.getByLabelText("A B"), { target: { value: "y" } });
  expect(change).toHaveBeenLastCalledWith("y");
});

it("renders a number from an integer or number schema", async () => {
  const change = draw({ type: ["integer", "null"], minimum: 1 }, 3);
  const input = screen.getByLabelText("A B");
  expect(input).toHaveAttribute("type", "number");
  expect(input).toHaveAttribute("min", "1");
  await userEvent.clear(input);
  expect(change).toHaveBeenLastCalledWith(null);
  fireEvent.change(input, { target: { value: "5" } });
  expect(change).toHaveBeenLastCalledWith(5);
});

it("renders a boolean as a toggle that falls back to the default", async () => {
  const change = draw({ type: ["boolean", "null"] }, null, { fallback: true });
  expect(screen.getByRole("checkbox")).toBeChecked();
  await userEvent.click(screen.getByRole("checkbox"));
  expect(change).toHaveBeenCalledWith(false);
});

it("returns a toggle to unset when it is set back to the default", async () => {
  const change = draw({ type: ["boolean", "null"] }, false, { fallback: true });
  await userEvent.click(screen.getByRole("checkbox"));
  expect(change).toHaveBeenCalledWith(null);
});

it("renders an enum as a select, the default marked and choosing it leaving the key unset", async () => {
  const change = draw({ type: ["string", "null"], enum: ["human", "auto", null] }, "human", { fallback: "auto" });
  const select = screen.getByRole("combobox");
  expect(select).toHaveValue("human");
  expect(screen.getAllByRole("option").map(o => o.textContent)).toEqual(["human", "auto (default)"]);
  await userEvent.selectOptions(select, "auto");
  expect(change).toHaveBeenLastCalledWith(null);
});

it("selects an unset enum's default", () => {
  draw({ type: ["string", "null"], enum: ["human", "auto", null] }, null, { fallback: "auto" });
  expect(screen.getByRole("combobox")).toHaveValue("auto");
});

it("shows an unset key's default as its value, and leaves it unset when the default is typed back", async () => {
  const change = draw({ type: ["integer", "null"] }, null, { fallback: 4 });
  const input = screen.getByLabelText("A B");
  expect(input).toHaveValue(4);
  fireEvent.change(input, { target: { value: "6" } });
  expect(change).toHaveBeenLastCalledWith(6);
  fireEvent.change(input, { target: { value: "4" } });
  expect(change).toHaveBeenLastCalledWith(null);
  await userEvent.clear(input);
  expect([input, change.mock.lastCall]).toEqual([expect.objectContaining({ value: "" }), [null]]);
});

it("writes a description in a textarea that grows with its text", () => {
  const change = vi.fn();
  render(<Field path={["application", "description"]} label="Description" node={{ type: ["string", "null"] }} value="A tax engine" fallback={null} onChange={change} />);
  const area = screen.getByLabelText("Description");
  expect(area.tagName).toBe("TEXTAREA");
  expect(area).toHaveValue("A tax engine");
  Object.defineProperty(area, "scrollHeight", { configurable: true, value: 90 });
  fireEvent.change(area, { target: { value: "A tax engine\nthat files returns" } });
  expect(change).toHaveBeenLastCalledWith("A tax engine\nthat files returns");
  expect(area.style.height).toBe("92px");
});

it("labels an enum's unset option when there is no default", () => {
  draw({ type: ["string", "null"], enum: ["a", null] }, null);
  expect(screen.getByRole("option", { name: "(unset)" })).toBeInTheDocument();
});

it("takes JSON for a type it has no control for, and keeps text that is not JSON", async () => {
  const change = draw({ type: ["array", "null"] }, ["x"]);
  const input = screen.getByLabelText("A B");
  expect(input).toHaveValue('["x"]');
  await userEvent.clear(input);
  expect(change).toHaveBeenLastCalledWith(null);
  fireEvent.change(input, { target: { value: "[1]" } });
  expect(change).toHaveBeenLastCalledWith([1]);
  fireEvent.change(input, { target: { value: "[1" } });
  expect(change).toHaveBeenLastCalledWith("[1");
});

it("shows the error beside the field and marks it invalid", () => {
  draw({ type: "string" }, "x", { error: "not allowed" });
  expect(screen.getByRole("alert")).toHaveTextContent("not allowed");
  expect(screen.getByLabelText("A B")).toHaveAttribute("aria-invalid", "true");
});

it("renders an empty help line for a key without a description", () => {
  draw({ type: "string" }, "x");
  expect(screen.getByLabelText("A B")).toBeInTheDocument();
});

it("puts a checkbox before its label, and any other control after it", () => {
  const { container, unmount } = render(<Field path={["x"]} label="X" node={{ type: "boolean" }} value={true} fallback={undefined} onChange={vi.fn()} />);
  expect(container.querySelector(".set-field.is-check")!.firstElementChild!.tagName).toBe("INPUT");
  unmount();
  const text = render(<Field path={["x"]} label="X" node={{ type: "string" }} value="v" fallback={undefined} onChange={vi.fn()} />);
  expect(text.container.querySelector(".set-field:not(.is-check)")!.firstElementChild!.tagName).toBe("LABEL");
});
