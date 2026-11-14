import { fireEvent, render, screen } from "@testing-library/react";
import { Nav } from "./Nav";

it("marks the open page and navigates on a plain click", () => {
  const go = vi.fn();
  render(<Nav route="/" onNavigate={go} />);
  expect(screen.getByRole("link", { name: "Board" })).toHaveAttribute("aria-current", "page");
  fireEvent.click(screen.getByRole("link", { name: "Plan dependencies" }));
  expect(go).toHaveBeenCalledWith("/dependencies");
});

it("leaves a modified click to the browser", () => {
  const go = vi.fn();
  render(<Nav route="/" onNavigate={go} />);
  // jsdom cannot navigate: swallow the default the browser would have followed.
  const swallow = (e: Event) => e.preventDefault();
  document.addEventListener("click", swallow);
  fireEvent.click(screen.getByRole("link", { name: "Plan dependencies" }), { ctrlKey: true });
  document.removeEventListener("click", swallow);
  expect(go).not.toHaveBeenCalled();
});

it("lists the three pages in order and navigates to settings", () => {
  const go = vi.fn();
  render(<Nav route="/settings" onNavigate={go} />);
  expect(screen.getAllByRole("link").map(l => l.textContent)).toEqual(["Board", "Plan dependencies", "Project settings"]);
  expect(screen.getByRole("link", { name: "Project settings" })).toHaveAttribute("aria-current", "page");
  fireEvent.click(screen.getByRole("link", { name: "Project settings" }));
  expect(go).toHaveBeenCalledWith("/settings");
});
