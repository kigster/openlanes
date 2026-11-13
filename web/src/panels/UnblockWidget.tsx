// The unblock widget a red pill toggles: docked at the top under the tabs, ringed in the highlight colour, with the
// plan's question and an answer box as wide as the widget. It shares its card, and its draft, with Needs you.
import { useEffect, type KeyboardEvent } from "react";
import type { Plan } from "../api/types";
import { AskCard } from "./AskCard";
import { asksOf } from "./question";
import { useReopened, useSettled } from "./asks";
import type { SendCommand } from "./support";

export interface UnblockWidgetProps {
  /** The plan whose red pill was clicked, or null when the widget is hidden. */
  plan: Plan | null;
  onCommand: SendCommand;
  /** Hide, Esc, a hold that faded out, or the plan no longer being blocked. */
  onClose: () => void;
}

export function UnblockWidget({ plan, onCommand, onClose }: UnblockWidgetProps) {
  useReopened(plan ? [plan] : []);
  const settled = useSettled();
  // Opened from the pill, a held question shows too: tagged held blocked, with Release hold.
  const ask = plan ? asksOf([plan]).find((a) => !settled.some((s) => s.id === a.id)) : undefined;
  // It closes itself once the plan is unblocked, by an answer from here or from anywhere else.
  useEffect(() => {
    if (plan && !ask) onClose();
  }, [plan, ask, onClose]);
  if (!plan || !ask) return null;
  const onKeyDown = (e: KeyboardEvent) => {
    if (e.key === "Escape") { e.preventDefault(); onClose(); }
  };
  return (
    <section className="unblock" role="region" aria-labelledby="unblock-title" onKeyDown={onKeyDown}>
      <div className="unblock-head">
        <h2 id="unblock-title">Unblock {plan.ordinal}: {plan.title}</h2>
        <button type="button" className="btn btn-quiet" onClick={onClose}>Hide</button>
      </div>
      <div className="unblock-body">
        <AskCard key={ask.id} ask={ask} variant="widget" onCommand={onCommand} onLeft={onClose} />
      </div>
    </section>
  );
}
