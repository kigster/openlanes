import type { ReactNode } from "react";
import { DependenciesPage } from "../dependencies/DependenciesPage";
import { SettingsMenu } from "../settings/SettingsMenu";
import { SettingsPage } from "../settings/SettingsPage";
import { revealPane } from "../settings/reveal";
import { revealWorktree } from "../worktrees/reveal";
import { WorktreesMenu } from "../worktrees/WorktreesMenu";
import { WorktreesPage } from "../worktrees/WorktreesPage";
import { HelpDialog } from "../panels";
import { Nav } from "./Nav";
import { ThemeMenu } from "./ThemeMenu";
import { useRoute } from "./useRoute";

/**
 * Page selection: the nav, and the page the URL names. The board (children) stays mounted while hidden, so its tab,
 * drawer and stream state survive a visit to the graph.
 */
export function Pages({ children }: { children: ReactNode }) {
  const { route, navigate } = useRoute();
  const settingsMenu = (close: () => void) => (
    <SettingsMenu
      onPick={id => {
        close();
        navigate("/settings");
        revealPane(id);
      }}
    />
  );
  const worktreesMenu = (close: () => void) => (
    <WorktreesMenu
      onPick={id => {
        close();
        navigate("/worktrees");
        revealWorktree(id);
      }}
    />
  );
  return (
    <>
      <Nav route={route} onNavigate={navigate} menus={{ "/settings": settingsMenu, "/worktrees": worktreesMenu }}
        tools={
          <>
            <ThemeMenu />
            <HelpDialog />
          </>
        }
      />
      {route === "/dependencies" && <DependenciesPage />}
      {route === "/settings" && <SettingsPage />}
      {route === "/worktrees" && <WorktreesPage />}
      <div className="page-board" style={{ display: route === "/" ? "contents" : "none" }}>
        {children}
      </div>
    </>
  );
}
