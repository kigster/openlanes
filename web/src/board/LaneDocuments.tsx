// The "Documents" dropdown at the foot of a wide lane's details block. It lists the plan's markdown under English labels
// and opens one in the read-only document modal. Narrow lanes never mount it, so they cost the server nothing.
import { useState } from "react";
import * as Menu from "@radix-ui/react-dropdown-menu";
import { DocumentModal } from "../panels/DocumentModal";
import type { Document } from "../panels/documents";
import { useDocuments } from "../panels/useDocuments";

export interface LaneDocumentsProps {
  ordinal: string;
  /** "narrow" fetches nothing and shows nothing. */
  lanes?: "wide" | "narrow";
}

export function LaneDocuments({ ordinal, lanes = "wide" }: LaneDocumentsProps) {
  const enabled = lanes === "wide";
  const { documents, loading } = useDocuments(ordinal, enabled);
  const [open, setOpen] = useState<Document | null>(null);
  if (!enabled) return null;
  const empty = !loading && documents.length === 0;
  return (
    <div className="plan-actions">
      <Menu.Root>
        <Menu.Trigger
          className="btn doc-trigger" disabled={empty} aria-label={`Documents of ${ordinal}`}
          title={empty ? "This plan has no documents yet" : "Read this plan's documents"}
        >
          Documents <span aria-hidden="true">▾</span>
        </Menu.Trigger>
        <Menu.Portal>
          <Menu.Content className="menu" align="start" sideOffset={4} loop>
            {documents.map((doc) => (
              <Menu.Item key={doc.name} className="menu-item" onSelect={() => setOpen(doc)}>
                <span className="menu-title">{doc.label}</span>
              </Menu.Item>
            ))}
          </Menu.Content>
        </Menu.Portal>
      </Menu.Root>
      {open && <DocumentModal ordinal={ordinal} document={open} onClose={() => setOpen(null)} />}
    </div>
  );
}
