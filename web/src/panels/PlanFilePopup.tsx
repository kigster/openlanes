// The one popup that shows a plan's markdown file, rendered, and lets the person edit its body when the file may be
// edited. Mounted means open: the drawer mounts it for a chosen name and unmounts it on close, so there is never a
// second. The frontmatter is shown read only and sent back untouched.
import { useEffect, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { getSession } from "../api/client";
import { PlanFileError, readPlanFile, savePlanFile } from "../api/planFiles";
import { Frame } from "./dialogs";
import { MarkdownEditor } from "./MarkdownEditor";
import { renderMarkdown } from "./markdown";
import { joinPlanFile, splitPlanFile, type SplitFile } from "./planFile";

export interface PlanFilePopupProps {
  ordinal: string;
  name: string;
  /** False for any name outside spec.md and plan.md, and while the plan has a live car. */
  editable: boolean;
  onClose: () => void;
}

interface Loaded extends SplitFile {
  etag: string;
}

/** The reason a refused save shows: the server's words, plus what to do about a changed file. */
function describe(error: unknown): string {
  if (error instanceof PlanFileError) {
    if (error.status === 412) return "Conflict: the file changed on disk since you opened it. Close this and open it again; your text is kept here until you do.";
    if (error.status === 409) return `Conflict: ${error.reason ?? "an agent is working on this plan"}. Your text is kept.`;
    return error.reason ?? error.message;
  }
  return error instanceof Error ? error.message : "Could not save.";
}

export function PlanFilePopup({ ordinal, name, editable, onClose }: PlanFilePopupProps) {
  const [file, setFile] = useState<Loaded | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    setFile(null);
    setFailure(null);
    setEditing(false);
    setSaveError(null);
    readPlanFile(ordinal, name).then(
      (read) => { if (live) setFile({ ...splitPlanFile(read.body), etag: read.etag }); },
      (error: unknown) => { if (live) setFailure(describe(error)); },
    );
    return () => { live = false; };
  }, [ordinal, name]);

  const startEditing = () => {
    if (!file) return;
    setDraft(file.body);
    setSaveError(null);
    setEditing(true);
  };

  const save = async () => {
    if (!file || saving) return;
    setSaving(true);
    setSaveError(null);
    try {
      const { csrf } = await getSession();
      const { etag } = await savePlanFile(ordinal, name, joinPlanFile({ frontmatter: file.frontmatter, body: draft }), file.etag, csrf);
      setFile({ frontmatter: file.frontmatter, body: draft, etag });
      setEditing(false);
    } catch (error) {
      setSaveError(describe(error));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog.Root open onOpenChange={(open) => { if (!open) onClose(); }}>
      <Frame
        className="plan-file"
        title={`${ordinal} ${name}`}
        description={<Dialog.Description className="plan-file-note">{editable ? "Edit the body; the frontmatter is read only." : "Read only."}</Dialog.Description>}
      >
        <div className="plan-file-body">
          {failure && <p role="alert" className="plan-file-error">{failure}</p>}
          {!file && !failure && <p aria-busy="true">Loading…</p>}
          {file && !editing && (
            <>
              {file.frontmatter && <pre className="plan-file-frontmatter" aria-label="Frontmatter">{file.frontmatter}</pre>}
              <div className="md-preview plan-file-preview" aria-label={`${name} rendered`} dangerouslySetInnerHTML={{ __html: renderMarkdown(file.body) }} />
            </>
          )}
          {file && editing && (
            <>
              {file.frontmatter && <pre className="plan-file-frontmatter" aria-label="Frontmatter">{file.frontmatter}</pre>}
              <MarkdownEditor value={draft} onChange={setDraft} label={`Edit ${name}`} preview={false} height="320px" autoFocus />
            </>
          )}
          {saveError && <p role="alert" className="plan-file-error">{saveError}</p>}
        </div>
        <div className="help-foot">
          {file && editable && !editing && <button type="button" className="btn btn-primary" onClick={startEditing}>Edit</button>}
          {editing && <button type="button" className="btn btn-primary" disabled={saving} onClick={save}>Save</button>}
          {editing && <button type="button" className="btn btn-quiet" disabled={saving} onClick={() => setEditing(false)}>Cancel</button>}
          <Dialog.Close className="btn btn-quiet">Close</Dialog.Close>
        </div>
      </Frame>
    </Dialog.Root>
  );
}
