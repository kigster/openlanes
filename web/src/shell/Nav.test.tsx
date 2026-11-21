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

it("lists the four pages in order and navigates to settings", () => {
  const go = vi.fn();
  render(<Nav route="/settings" onNavigate={go} />);
  expect(screen.getAllByRole("link").map(l => l.textContent)).toEqual(["Board", "Plan dependencies", "Project settings", "Worktrees"]);
  expect(screen.getByRole("link", { name: "Project settings" })).toHaveAttribute("aria-current", "page");
  fireEvent.click(screen.getByRole("link", { name: "Project settings" }));
  expect(go).toHaveBeenCalledWith("/settings");
});

it("opens a page's drop-down by hover or by its ▾ button, and closes it on Escape or a pick", () => {
  const picked = vi.fn();
  const menus = { "/settings": (close: () => void) => <button onClick={() => { picked(); close(); }}>General</button> } as const;
  render(<Nav route="/" onNavigate={vi.fn()} menus={menus} />);
  const caret = screen.getByRole("button", { name: "Project settings sections" });
  expect(caret).toHaveAttribute("aria-expanded", "false");
  expect(screen.queryByRole("button", { name: "General" })).not.toBeInTheDocument();
  fireEvent.mouseEnter(caret.parentElement!);
  expect(screen.getByRole("group", { name: "Project settings sections" })).toBeInTheDocument();
  fireEvent.mouseLeave(caret.parentElement!);
  expect(screen.queryByRole("group")).not.toBeInTheDocument();
  // A click under a pointer that already opened it by hover keeps it open.
  fireEvent.mouseEnter(caret.parentElement!);
  fireEvent.click(caret);
  fireEvent.mouseLeave(caret.parentElement!);
  expect(screen.getByRole("group")).toBeInTheDocument();
  fireEvent.blur(caret, { relatedTarget: screen.getByRole("button", { name: "General" }) });
  expect(screen.getByRole("group")).toBeInTheDocument();
  fireEvent.blur(caret, { relatedTarget: null });
  expect(screen.queryByRole("group")).not.toBeInTheDocument();
  fireEvent.click(caret);
  fireEvent.keyDown(caret, { key: "Escape" });
  expect(screen.queryByRole("group")).not.toBeInTheDocument();
  fireEvent.keyDown(caret, { key: "Enter" });
  fireEvent.click(caret);
  fireEvent.click(screen.getByRole("button", { name: "General" }));
  expect(picked).toHaveBeenCalled();
  expect(screen.queryByRole("group")).not.toBeInTheDocument();
  expect(screen.getAllByRole("link")).toHaveLength(4);
});
