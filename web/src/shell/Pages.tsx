import type { ReactNode } from "react";
import { DependenciesPage } from "../dependencies/DependenciesPage";
import { Nav } from "./Nav";
import { useRoute } from "./useRoute";

/**
 * Page selection: the nav, and the page the URL names. The board (children) stays mounted while hidden, so its tab,
 * drawer and stream state survive a visit to the graph.
 */
export function Pages({ children }: { children: ReactNode }) {
  const { route, navigate } = useRoute();
  return (
    <>
      <Nav route={route} onNavigate={navigate} />
      {route === "/dependencies" && <DependenciesPage />}
      <div className="page-board" style={{ display: route === "/" ? "contents" : "none" }}>
        {children}
      </div>
    </>
  );
}
