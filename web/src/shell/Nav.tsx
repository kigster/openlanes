import { useState, type MouseEvent, type ReactNode } from "react";
import type { Route } from "./useRoute";

const PAGES: Array<{ route: Route; label: string }> = [
  { route: "/", label: "Board" },
  { route: "/dependencies", label: "Plan dependencies" },
  { route: "/settings", label: "Project settings" },
  { route: "/worktrees", label: "Worktrees" },
];

/** A page's drop-down, drawn only while open; `close` folds it once an entry is picked. */
export type NavMenu = (close: () => void) => ReactNode;

interface Props {
  route: Route;
  onNavigate: (to: Route) => void;
  menus?: Partial<Record<Route, NavMenu>>;
  /** Controls for every page, at the right end of the bar: the theme chooser and help. */
  tools?: ReactNode;
}

/** The page links, fixed to the top. A plain click switches page in place; a modified one opens the real address. */
export function Nav({ route, onNavigate, menus = {}, tools }: Props) {
  const go = (to: Route) => (e: MouseEvent<HTMLAnchorElement>) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    onNavigate(to);
  };
  return (
    <nav className="page-nav" aria-label="Pages">
      <ul>
        {PAGES.map(p => {
          const link = (
            <a href={p.route} aria-current={p.route === route ? "page" : undefined} onClick={go(p.route)}>
              {p.label}
            </a>
          );
          const menu = menus[p.route];
          return <li key={p.route}>{menu ? <Dropdown label={p.label} menu={menu}>{link}</Dropdown> : link}</li>;
        })}
      </ul>
      {tools && <div className="page-tools">{tools}</div>}
    </nav>
  );
}

/**
 * Opens on hover (pointer) or the ▾ button (touch, keyboard). The two are kept apart, so a click on ▾ under a pointer
 * that already opened it by hover pins it open rather than closing it. Escape, a pick, or focus leaving it closes it.
 */
function Dropdown({ label, menu, children }: { label: string; menu: NavMenu; children: ReactNode }) {
  const [hovered, setHovered] = useState(false);
  const [pinned, setPinned] = useState(false);
  const open = hovered || pinned;
  const close = () => {
    setHovered(false);
    setPinned(false);
  };
  return (
    <div
      className="page-dropdown"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onKeyDown={e => e.key === "Escape" && close()}
      onBlur={e => !e.currentTarget.contains(e.relatedTarget) && setPinned(false)}
    >
      {children}
      <button type="button" className="page-caret" aria-haspopup="true" aria-expanded={open} aria-label={`${label} sections`} onClick={() => setPinned(p => !p)}>
        ▾
      </button>
      {open && (
        <div className="page-menu" role="group" aria-label={`${label} sections`}>
          {menu(close)}
        </div>
      )}
    </div>
  );
}
