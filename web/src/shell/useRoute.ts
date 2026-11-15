import { useCallback, useEffect, useState } from "react";

export type Route = "/" | "/dependencies" | "/settings";

const PAGES: Route[] = ["/dependencies", "/settings"];

/** Any path but a page's own is the board, so an unknown address still lands on something. */
export const routeOf = (pathname: string): Route => PAGES.find(r => r === pathname.replace(/\/+$/, "")) ?? "/";

/** The page the URL names, and a way to change it without a reload: history.pushState plus popstate for Back. */
export function useRoute() {
  const [route, setRoute] = useState<Route>(() => routeOf(window.location.pathname));
  useEffect(() => {
    const onPop = () => setRoute(routeOf(window.location.pathname));
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);
  const navigate = useCallback((to: Route) => {
    if (routeOf(window.location.pathname) !== to) window.history.pushState(null, "", to + window.location.search);
    setRoute(to);
  }, []);
  return { route, navigate };
}
