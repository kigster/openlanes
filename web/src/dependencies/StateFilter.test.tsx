import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { StateFilter } from "./StateFilter";
import { graph } from "./fixture";

it("draws a checkbox per state in order and reports a toggle", async () => {
  const toggle = vi.fn();
  render(<StateFilter states={graph.states} checked={new Set(["building"])} onToggle={toggle} />);
  const boxes = screen.getAllByRole("checkbox");
  expect(boxes.map(b => (b as HTMLInputElement).checked)).toEqual([true, false, false]);
  await userEvent.click(screen.getByRole("checkbox", { name: /Approved/ }));
  expect(toggle).toHaveBeenCalledWith("approved");
});
