import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Field } from "./Field";

const draw = (node: object, value: unknown, extra: Partial<Parameters<typeof Field>[0]> = {}) => {
  const onChange = vi.fn();
  render(<Field path={["a", "b"]} node={node} value={value} fallback={undefined} onChange={onChange} {...extra} />);
  return onChange;
};

it("renders text with its label and help line, and sends null when emptied", async () => {
  const change = draw({ type: ["string", "null"], description: "Help me" }, "x");
  expect(screen.getByLabelText("a.b")).toHaveValue("x");
  expect(screen.getByText("Help me")).toBeInTheDocument();
  await userEvent.clear(screen.getByLabelText("a.b"));
  expect(change).toHaveBeenLastCalledWith(null);
  fireEvent.change(screen.getByLabelText("a.b"), { target: { value: "y" } });
  expect(change).toHaveBeenLastCalledWith("y");
});

it("renders a number from an integer or number schema", async () => {
  const change = draw({ type: ["integer", "null"], minimum: 1 }, 3);
  const input = screen.getByLabelText("a.b");
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

it("renders an enum as a select, with unset as the empty option", async () => {
  const change = draw({ type: ["string", "null"], enum: ["human", "auto", null] }, "human", { fallback: "auto" });
  const select = screen.getByRole("combobox");
  expect(select).toHaveValue("human");
  expect(screen.getByRole("option", { name: "(default: auto)" })).toBeInTheDocument();
  await userEvent.selectOptions(select, "auto");
  expect(change).toHaveBeenLastCalledWith("auto");
  await userEvent.selectOptions(select, "");
  expect(change).toHaveBeenLastCalledWith(null);
});

it("labels an enum's unset option when there is no default", () => {
  draw({ type: ["string", "null"], enum: ["a", null] }, null);
  expect(screen.getByRole("option", { name: "(unset)" })).toBeInTheDocument();
});

it("takes JSON for a type it has no control for, and keeps text that is not JSON", async () => {
  const change = draw({ type: ["array", "null"] }, ["x"]);
  const input = screen.getByLabelText("a.b");
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
  expect(screen.getByLabelText("a.b")).toHaveAttribute("aria-invalid", "true");
});

it("renders an empty help line for a key without a description", () => {
  draw({ type: "string" }, "x");
  expect(screen.getByLabelText("a.b")).toBeInTheDocument();
});
