import type { MouseEvent } from "react";
import type { Route } from "./useRoute";

const PAGES: Array<{ route: Route; label: string }> = [
  { route: "/", label: "Board" },
  { route: "/dependencies", label: "Plan dependencies" },
  { route: "/settings", label: "Project settings" },
];

/** The page links, fixed to the top. A plain click switches page in place; a modified one opens the real address. */
export function Nav({ route, onNavigate }: { route: Route; onNavigate: (to: Route) => void }) {
  const go = (to: Route) => (e: MouseEvent<HTMLAnchorElement>) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    onNavigate(to);
  };
  return (
    <nav className="page-nav" aria-label="Pages">
      <ul>
        {PAGES.map(p => (
          <li key={p.route}>
            <a href={p.route} aria-current={p.route === route ? "page" : undefined} onClick={go(p.route)}>
              {p.label}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
