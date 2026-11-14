// A plan document, read only, in a modal that sizes itself to the viewport (panels.css, .document-modal). Mounted means
// open, as PlanFilePopup is: the lane mounts it for a chosen document and unmounts it on close. Editing stays in the drawer.
import { useEffect, useRef, useState } from "react";
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

const describe = (error: unknown): string =>
  error instanceof PlanFileError ? (error.reason ?? error.message) : error instanceof Error ? error.message : "Could not read the document.";

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

  // The diagrams are drawn into the rendered node after it mounts; a re-render of the same HTML leaves them be.
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
            <Dialog.Close className="document-modal-x" aria-label="Close">[x]</Dialog.Close>
          </div>
          <div className="document-modal-body">
            {failure && <p role="alert" className="plan-file-error">{failure}</p>}
            {!file && !failure && <p aria-busy="true">Loading…</p>}
            {file && (
              <>
                {file.frontmatter && (
                  <div className="document-frontmatter" aria-label="Frontmatter" dangerouslySetInnerHTML={{ __html: renderFrontmatter(file.frontmatter) }} />
                )}
                <div ref={preview} className="md-preview document-preview" aria-label={`${doc.label} rendered`} dangerouslySetInnerHTML={{ __html: renderMarkdown(file.body) }} />
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
