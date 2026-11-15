// The "Documents" dropdown at the foot of a wide lane's details block. It lists the plan's markdown under English labels
// and opens one in the read-only document modal. This component alone decides whether the strip exists: a narrow lane
// renders nothing and costs the server nothing, so no stylesheet rule repeats that.
import { useState } from "react";
import * as Menu from "@radix-ui/react-dropdown-menu";
import { DocumentModal } from "../panels/DocumentModal";
import type { Document } from "../panels/documents";
import { useDocuments } from "../panels/useDocuments";

export interface LaneDocumentsProps {
  ordinal: string;
  /** "narrow" fetches nothing and shows no menu. A document already open stays open. */
  lanes?: "wide" | "narrow";
}

export function LaneDocuments({ ordinal, lanes = "wide" }: LaneDocumentsProps) {
  const enabled = lanes === "wide";
  const { documents, loading, error, refetch } = useDocuments(ordinal, enabled);
  const [open, setOpen] = useState<Document | null>(null);
  // One line when there is nothing to list, so the menu never opens empty. The trigger stays enabled throughout:
  // opening it reads the list again, which is the only retry a failed or empty lane has.
  const note =
    loading && documents.length === 0 ? "Loading\u2026"
    : error ? `Could not list the documents: ${error.message}`
    : documents.length === 0 ? "This plan has no documents yet"
    : null;
  // The modal sits beside the strip, not inside it, and so keeps its place in the tree when the strip goes: a lane
  // turns narrow when an agent starts on its plan, and that must neither close nor reload what a person is reading.
  return (
    <>
      {enabled && (
        <div className="plan-actions">
          <Menu.Root onOpenChange={(opened) => { if (opened) refetch(); }}>
            <Menu.Trigger className="btn doc-trigger" aria-label={`Documents of ${ordinal}`} title="Read this plan's documents">
              Documents <span aria-hidden="true">▾</span>
            </Menu.Trigger>
            <Menu.Portal>
              <Menu.Content className="menu" align="start" sideOffset={4} loop>
                {documents.map((doc) => (
                  <Menu.Item key={doc.name} className="menu-item" onSelect={() => setOpen(doc)}>
                    <span className="menu-title">{doc.label}</span>
                  </Menu.Item>
                ))}
                {note && (
                  <Menu.Item className="menu-item" disabled aria-busy={loading || undefined}>
                    <span className="menu-sub">{note}</span>
                  </Menu.Item>
                )}
              </Menu.Content>
            </Menu.Portal>
          </Menu.Root>
        </div>
      )}
      {open && <DocumentModal ordinal={ordinal} document={open} onClose={() => setOpen(null)} />}
    </>
  );
}
