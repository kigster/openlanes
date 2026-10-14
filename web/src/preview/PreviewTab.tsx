import { postAppCommand } from "../api/client";
import { planId } from "../board/format";
import { openWindow, type RunningApp } from "./model";
import { PreviewToolbar, type SendAppCommand } from "./PreviewToolbar";
import "./preview.css";

/**
 * One running app (M13): its toolbar, then the preview process in an iframe, or, when the app's headers refuse to be
 * framed, a way to open it in a window of its own. The runner reads those headers, since the page cannot: a refused
 * frame still fires `load`. Plan 014 adds the mirror of its headless browser beside this.
 */
export function PreviewTab({ app, send = postAppCommand }: { app: RunningApp; send?: SendAppCommand }) {
  const { preview } = app;
  return (
    <section className="preview" aria-label={`Preview of plan ${planId(app.plan)}`}>
      <div className="preview-head">
        <h2>
          {planId(app.plan)} · {app.branch} · <span className="preview-port">:{preview.port}</span>
        </h2>
        <p>
          {app.processes.map(p => `${p.process} :${p.port}`).join(" · ")}
        </p>
      </div>
      <PreviewToolbar app={app} send={send} />
      {preview.state === "ready" && preview.framing === "frame" ? (
        // Keyed on when it became ready, so a restart of the previewed process reloads the frame.
        <iframe key={preview.at} className="preview-frame" title={`${preview.process} of plan ${planId(app.plan)}`} src={preview.url} />
      ) : preview.framing === "window" ? (
        <div className="preview-note">
          <p>This app refuses to be shown in a frame (X-Frame-Options or frame-ancestors), so it opens in a window of its own.</p>
          <button type="button" className="btn btn-primary" onClick={() => openWindow(preview.url)}>
            Open {preview.url} in a new window
          </button>
        </div>
      ) : (
        <div className="preview-note">
          <p>{preview.state === "failed" ? `${preview.process} did not start.` : `${preview.process} is starting on port ${preview.port}…`}</p>
        </div>
      )}
    </section>
  );
}
