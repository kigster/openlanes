import "./fold.css";

/** The −/+ box that folds a panel: drawn as bars (fold.css), named "Open X" or "Collapse X" for whoever cannot see them. */
export function FoldToggle({ open, title, onToggle }: { open: boolean; title: string; onToggle: () => void }) {
  return (
    <button type="button" className="fold-toggle" aria-expanded={open} aria-label={`${open ? "Collapse" : "Open"} ${title}`} onClick={onToggle}>
      {open ? "−" : "+"}
    </button>
  );
}
