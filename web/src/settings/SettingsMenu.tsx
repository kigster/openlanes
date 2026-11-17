import { useMemo } from "react";
import { useSettings } from "../api/settings";
import { panesOf } from "./model";

/**
 * The nav's drop-down under "Project settings": one entry per outer pane. Mounted only while open, so the board never
 * fetches the settings until someone asks for the list; the page and the menu then share the one cached query.
 */
export function SettingsMenu({ onPick }: { onPick: (paneId: string) => void }) {
  const { data, error } = useSettings();
  const panes = useMemo(() => (data ? panesOf(data) : []), [data]);
  if (error) return <p className="page-menu-note">Settings unavailable</p>;
  if (!data) return <p className="page-menu-note">Loading…</p>;
  return (
    <ul>
      {panes.map(p => (
        <li key={p.id}>
          <button type="button" onClick={() => onPick(p.id)}>{p.title}</button>
        </li>
      ))}
    </ul>
  );
}
