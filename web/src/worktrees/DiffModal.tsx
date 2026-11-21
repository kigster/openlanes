// A worktree branch's diff against the default branch, read from the server's local git (GitHub refuses to be framed),
// with a link to the same comparison on GitHub. Mounted means open, as DocumentModal is.
import * as Dialog from "@radix-ui/react-dialog";
import { useWorktreeDiff, type Worktree } from "../api/worktrees";

/** A patch line's class: additions green, removals red, hunk headers dim. File headers (+++/---) stay plain. */
const lineClass = (line: string): string | undefined =>
  line.startsWith("+++") || line.startsWith("---") ? "wt-diff-file"
  : line.startsWith("+") ? "wt-diff-add"
  : line.startsWith("-") ? "wt-diff-del"
  : line.startsWith("@@") ? "wt-diff-hunk"
  : undefined;

export function DiffModal({ worktree, onClose }: { worktree: Worktree; onClose: () => void }) {
  const { data, error, isLoading } = useWorktreeDiff(worktree.id, true);
  const branch = worktree.branch || "detached HEAD";
  return (
    <Dialog.Root open onOpenChange={open => { if (!open) onClose(); }}>
      <Dialog.Portal>
        <Dialog.Overlay className="dialog-overlay" />
        <Dialog.Content className="document-modal wt-diff-modal" aria-describedby={undefined}>
          <div className="document-modal-head">
            <Dialog.Title asChild><h2>{`${branch} against ${data?.base ?? "main"}`}</h2></Dialog.Title>
            <Dialog.Close className="document-modal-x" aria-label="[x] Close">[x]</Dialog.Close>
          </div>
          <div className="document-modal-body" role="region" tabIndex={0} aria-label={`Diff of ${branch}`}>
            {error && <p role="alert" className="plan-file-error">Could not read the diff: {error.message}</p>}
            {isLoading && <p aria-busy="true">Loading…</p>}
            {data && (
              <>
                <pre className="wt-diff-stat">{data.stat || "No changes against the base."}</pre>
                {data.patch && (
                  <pre className="wt-diff-patch" aria-label="Patch">
                    {data.patch.split("\n").map((line, i) => (
                      <span key={i} className={lineClass(line)}>{line}{"\n"}</span>
                    ))}
                  </pre>
                )}
                {data.truncated && <p className="drawer-meta">The patch is cut short; GitHub has the rest.</p>}
              </>
            )}
          </div>
          <div className="document-modal-foot">
            {data?.compare_url && (
              <a className="btn" href={data.compare_url} target="_blank" rel="noreferrer">Open on GitHub</a>
            )}
            <Dialog.Close className="btn btn-quiet">Close</Dialog.Close>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
