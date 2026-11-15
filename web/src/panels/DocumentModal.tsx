// A plan document, read only, in a modal that sizes itself to the viewport (panels.css, .document-modal). Mounted means
// open, as PlanFilePopup is: the lane mounts it for a chosen document and unmounts it on close. Editing stays in the drawer.
import { useEffect, useMemo, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { PlanFileError, readPlanFile } from "../api/planFiles";
import type { Document } from "./documents";
import { renderFrontmatter, renderMarkdown } from "./markdown";
import { renderMermaid } from "./mermaid";
import { splitPlanFile, type SplitFile } from "./planFile";
import { useIsDark } from "./useIsDark";

export interface DocumentModalProps {
  ordinal: string;
  document: Document;
  onClose: () => void;
}

// The server's own sentence when it sent one. A 413 or 415 may come from a proxy with no JSON body, and then the
// fallback ("GET /api/... answered 413") says nothing a reader can act on.
const WITHOUT_REASON: Record<number, string> = {
  413: "This document is too large to show here. Open it in an editor.",
  415: "This document is not text, so it cannot be shown here.",
};

const describe = (error: unknown): string =>
  error instanceof PlanFileError ? (error.reason ?? WITHOUT_REASON[error.status] ?? error.message)
  : error instanceof Error ? error.message
  : "Could not read the document.";

export function DocumentModal({ ordinal, document: doc, onClose }: DocumentModalProps) {
  const [file, setFile] = useState<SplitFile | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const preview = useRef<HTMLDivElement>(null);
  const dark = useIsDark();

  useEffect(() => {
    let live = true;
    setFile(null);
    setFailure(null);
    readPlanFile(ordinal, doc.name).then(
      (read) => { if (live) setFile(splitPlanFile(read.body)); },
      (error: unknown) => { if (live) setFailure(describe(error)); },
    );
    return () => { live = false; };
  }, [ordinal, doc.name]);

  // The lane re-renders on every board event, several a second while an agent works. Parsing, sanitizing and
  // highlighting a long document each time held the page; the HTML changes only when the file read does.
  const frontmatter = useMemo(() => (file?.frontmatter ? renderFrontmatter(file.frontmatter) : null), [file]);
  const body = useMemo(() => (file ? renderMarkdown(file.body) : null), [file]);

  // The diagrams are drawn into the rendered node after it mounts; a re-render of the same HTML leaves them be, so the preview is keyed by theme: a switch remounts it and draws again.
  useEffect(() => {
    if (file && preview.current) void renderMermaid(preview.current, dark);
  }, [file, dark]);

  return (
    <Dialog.Root open onOpenChange={(open) => { if (!open) onClose(); }}>
      <Dialog.Portal>
        <Dialog.Overlay className="dialog-overlay" />
        <Dialog.Content className="document-modal" aria-describedby={undefined}>
          <div className="document-modal-head">
            <Dialog.Title asChild><h2>{`${ordinal} · ${doc.label}`}</h2></Dialog.Title>
            <Dialog.Close className="document-modal-x" aria-label="[x] Close">[x]</Dialog.Close>
          </div>
          {/* Focusable and named, so the arrow keys and Page Down scroll a document longer than the modal. */}
          <div className="document-modal-body" role="region" tabIndex={0} aria-label={`${doc.label} of ${ordinal}`}>
            {failure && <p role="alert" className="plan-file-error">{failure}</p>}
            {!file && !failure && <p aria-busy="true">Loading…</p>}
            {body !== null && (
              <>
                {frontmatter !== null && (
                  <div className="document-frontmatter" aria-label="Frontmatter" dangerouslySetInnerHTML={{ __html: frontmatter }} />
                )}
                <div key={dark ? "dark" : "light"} ref={preview} className="md-preview document-preview" aria-label={`${doc.label} rendered`} dangerouslySetInnerHTML={{ __html: body }} />
              </>
            )}
          </div>
          <div className="document-modal-foot">
            <Dialog.Close className="btn btn-quiet">Close</Dialog.Close>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
