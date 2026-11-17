// The confirm dialog behind each Plan Management action. Discard and Defer need the words their state is justified by
// (`discarded-reason.md`, and the trigger in `delayed.md`), so the dialog asks for them; Clear Dependencies names the
// plans the plan would stop waiting for.
import { useId, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useQueryClient } from "@tanstack/react-query";
import { Frame } from "../panels/dialogs";
import { actionLabel, runPlanAction, type PlanActionKey, type PlanOffer } from "../api/planActions";

const COPY: Record<PlanActionKey, { ask?: string; placeholder?: string; body: (o: PlanOffer) => string }> = {
  clear_dependencies: {
    body: o => `${o.ordinal} waits on ${o.depends_on.join(", ")}. Clearing its dependencies lets it start without them; spec.md keeps every other key as written.`,
  },
  discard: {
    ask: "Why is it discarded?",
    placeholder: "Superseded by 071.00",
    body: o =>
      `${o.running ? `The agents working on ${o.ordinal} are stopped first. ` : ""}It moves to ❌ Discarded and stays as a record. Its worktree, branch and pull requests are left as they are.`,
  },
  defer: {
    ask: "What should bring it back?",
    placeholder: "when the API is stable",
    body: o => `${o.running ? `The agents working on ${o.ordinal} are stopped first. ` : ""}It moves to 💤 Deferred and waits until what you name here happens.`,
  },
};

export function PlanActionDialog({ offer, action, onClose }: { offer: PlanOffer; action: PlanActionKey; onClose: () => void }) {
  const client = useQueryClient();
  const copy = COPY[action];
  const label = actionLabel(action, offer);
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const cancel = useRef<HTMLButtonElement>(null);
  const field = useId();
  const missing = copy.ask !== undefined && reason.trim() === "";
  const confirm = async () => {
    setPending(true);
    setError(null);
    try {
      await runPlanAction(offer, action, reason.trim());
      // The plan moved or its spec changed: every view of it reads again.
      await client.invalidateQueries();
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setPending(false);
    }
  };
  return (
    <Dialog.Root open onOpenChange={(open) => { if (!open && !pending) onClose(); }}>
      <Frame
        className="confirm" title={`${label}: ${offer.ordinal}?`}
        onOpenAutoFocus={(e) => { if (!copy.ask) { e.preventDefault(); cancel.current?.focus(); } }}
      >
        <div className="help-body">
          <Dialog.Description>{copy.body(offer)}</Dialog.Description>
          {copy.ask && (
            <label className="plan-action-reason" htmlFor={field}>
              <span>{copy.ask}</span>
              <textarea id={field} rows={3} value={reason} placeholder={copy.placeholder} onChange={(e) => setReason(e.target.value)} />
            </label>
          )}
          {error && <p className="plan-action-error" role="alert">{error}</p>}
        </div>
        <div className="help-foot">
          <Dialog.Close className="btn btn-quiet" ref={cancel} disabled={pending}>Cancel</Dialog.Close>
          <button type="button" className={`btn ${action === "discard" ? "btn-alarm" : "btn-primary"}`} disabled={pending || missing} onClick={confirm}>
            {pending ? "Working…" : label}
          </button>
        </div>
      </Frame>
    </Dialog.Root>
  );
}
