import { useState } from "react";
import type { AppCommand } from "../api/types";
import { backend, openWindow, overall, type RunningApp } from "./model";

export type SendAppCommand = (command: AppCommand) => Promise<unknown>;

const SAYS = { running: "● running", restarting: "◐ restarting", failed: "✕ failed" } as const;

/**
 * The Preview tab's toolbar (M13): where the app stands, and Restart backend, Open in new window and Stop. The buttons
 * only ask; what happened comes back as the app's states on the event stream.
 */
export function PreviewToolbar({ app, send }: { app: RunningApp; send: SendAppCommand }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const state = overall(app);
  const failed = app.processes.find(p => p.state === "failed");

  const ask = (command: Omit<AppCommand, "plan">) => {
    setBusy(true);
    setError(null);
    send({ plan: app.plan, ...command })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setBusy(false));
  };

  return (
    <div className="preview-toolbar" role="toolbar" aria-label={`App of plan ${app.plan}`}>
      <span className={`preview-state is-${state}`} role="status" aria-live="polite">
        {SAYS[state]}
        {failed ? `: ${failed.process}: ${failed.reason ?? "no reason given"}` : ""}
      </span>
      <span className="preview-actions">
        <button type="button" className="btn" disabled={busy || backend(app).length === 0} onClick={() => ask({ action: "restart", target: "backend" })}>
          Restart backend
        </button>
        <button type="button" className="btn" onClick={() => openWindow(app.preview.url)}>
          Open in new window
        </button>
        <button type="button" className="btn btn-alarm" disabled={busy} onClick={() => ask({ action: "stop" })}>
          Stop
        </button>
      </span>
      {error ? (
        <span className="preview-error" role="alert">
          {error}
        </span>
      ) : null}
    </div>
  );
}
