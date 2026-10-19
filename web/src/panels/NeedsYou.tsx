// The right rail: every question waiting on a person. A held question leaves the rail; its solid
// red pill in the status bar is the way back to it.
import type { Plan } from "../api/types";
import { AskCard } from "./AskCard";
import { asksOf } from "./question";
import { useSettled } from "./asks";
import type { SendCommand } from "./support";

export interface NeedsYouProps {
  plans: Plan[];
  onCommand: SendCommand;
}

export function NeedsYou({ plans, onCommand }: NeedsYouProps) {
  const settled = useSettled();
  const done = new Set(settled.map((s) => s.id));
  const all = asksOf(plans);
  const open = all.filter((a) => !done.has(a.id) && !(a.kind === "question" && a.question.held));
  // Settled cards sink below the open ones; a settled request the snapshot has dropped still shows its note.
  const settledCards = settled.map((s) => all.find((a) => a.id === s.id) ?? s);
  return (
    <aside className="rail" aria-labelledby="rail-title">
      <h2 id="rail-title">Needs you {open.length ? <span>({open.length})</span> : null}</h2>
      <p className="rail-sub">Questions wait here until you answer them.</p>
      <div className="asks" tabIndex={0} aria-label="Requests waiting on you">
        {open.length + settledCards.length === 0 ? (
          <p className="empty">Nothing waiting on you. Agents will ask here.</p>
        ) : (
          <>
            {open.map((ask) => <AskCard key={ask.id} ask={ask} variant="rail" onCommand={onCommand} />)}
            {settledCards.map((ask) => "kind" in ask
              ? <AskCard key={ask.id} ask={ask} variant="rail" onCommand={onCommand} />
              : <div key={ask.id} className="ask is-done" data-ask={ask.id}><p className="ask-done">{ask.note}</p></div>)}
          </>
        )}
      </div>
    </aside>
  );
}
