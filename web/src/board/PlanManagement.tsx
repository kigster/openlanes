// The "Plan Management" dropdown at the foot of a wide lane's details block, and on the dependency graph and the
// Worktrees page. Its top section lists the plan's markdown under English labels and opens one in the read-only
// document modal; under a divider, the Actions the server says this plan offers, each behind a confirm dialog.
// This component alone decides whether the strip exists: a narrow lane renders nothing and costs the server nothing.
import { useState } from "react";
import * as Menu from "@radix-ui/react-dropdown-menu";
import { DocumentModal } from "../panels/DocumentModal";
import type { Document } from "../panels/documents";
import { useDocuments } from "../panels/useDocuments";
import { actionLabel, usePlanOffer, type PlanActionKey, type PlanOffer } from "../api/planActions";
import { PlanActionDialog } from "./PlanActionDialog";

export interface PlanManagementProps {
  ordinal: string;
  /** "narrow" fetches nothing and shows no menu. A document already open stays open. */
  lanes?: "wide" | "narrow";
  /** Ask the server for the list only when the menu first opens: a page of sixty boxes must not make sixty requests. */
  lazy?: boolean;
  /** The class of the strip around the trigger, where the lane's own does not fit. */
  className?: string;
}

export function PlanManagement({ ordinal, lanes = "wide", lazy = false, className = "plan-actions" }: PlanManagementProps) {
  const enabled = lanes === "wide";
  const [asked, setAsked] = useState(!lazy);
  const { documents, loading, error, refetch } = useDocuments(ordinal, enabled && asked);
  const [open, setOpen] = useState<Document | null>(null);
  const [acting, setActing] = useState<{ key: PlanActionKey; offer: PlanOffer } | null>(null);
  // One line when there is nothing to list, so the section never sits empty. The trigger stays enabled throughout:
  // opening it reads the list again, which is the only retry a failed or empty lane has.
  const note =
    (loading || !asked) && documents.length === 0 ? "Loading…"
    : error ? `Could not list the documents: ${error.message}`
    : documents.length === 0 ? "This plan has no documents yet"
    : null;
  // The modal and the dialog sit beside the strip, not inside it, and so keep their place in the tree when the strip
  // goes: a lane turns narrow when an agent starts on its plan, and that must neither close nor reload them.
  return (
    <>
      {enabled && (
        <div className={className}>
          <Menu.Root
            onOpenChange={(now) => {
              if (!now) return;
              setAsked(true);
              refetch();
            }}
          >
            <Menu.Trigger className="btn doc-trigger" aria-label={`Plan Management of ${ordinal}`} title="This plan's documents and actions">
              Plan Management <span aria-hidden="true">▾</span>
            </Menu.Trigger>
            <Menu.Portal>
              <Menu.Content className="menu" align="start" sideOffset={4} loop>
                <Menu.Group aria-label="Documents">
                  <Menu.Label className="menu-label">Documents</Menu.Label>
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
                </Menu.Group>
                <Menu.Separator className="menu-separator" />
                <ActionsSection ordinal={ordinal} onPick={(key, offer) => setActing({ key, offer })} />
              </Menu.Content>
            </Menu.Portal>
          </Menu.Root>
        </div>
      )}
      {open && <DocumentModal ordinal={ordinal} document={open} onClose={() => setOpen(null)} />}
      {acting && <PlanActionDialog offer={acting.offer} action={acting.key} onClose={() => setActing(null)} />}
    </>
  );
}

/**
 * The menu's Actions, read each time the menu opens: it mounts only while the menu is open, so a lane never asks for
 * them up front, and a plan that moved since the last open offers what it offers now.
 */
function ActionsSection({ ordinal, onPick }: { ordinal: string; onPick: (key: PlanActionKey, offer: PlanOffer) => void }) {
  const offer = usePlanOffer(ordinal, true);
  const actions = offer.data?.actions ?? [];
  const note =
    !offer.data && offer.isFetching ? "Loading\u2026"
    : offer.error ? `Could not read the actions: ${offer.error.message}`
    : offer.data && actions.length === 0 ? "Nothing to do from this state"
    : null;
  return (
    <Menu.Group aria-label="Actions">
      <Menu.Label className="menu-label">Actions</Menu.Label>
      {offer.data && actions.map((key) => (
        <Menu.Item key={key} className={`menu-item${key === "discard" ? " menu-danger" : ""}`} onSelect={() => onPick(key, offer.data)}>
          <span className="menu-title">{actionLabel(key, offer.data)}</span>
        </Menu.Item>
      ))}
      {note && (
        <Menu.Item className="menu-item" disabled aria-busy={offer.isFetching || undefined}>
          <span className="menu-sub">{note}</span>
        </Menu.Item>
      )}
    </Menu.Group>
  );
}
