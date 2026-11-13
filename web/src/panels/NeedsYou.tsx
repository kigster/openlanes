// The right rail: every question waiting on a person. A held question leaves the rail; its solid
// red pill in the status bar is the way back to it. Unblock on a lane spotlights that plan's questions: they move
// to the front, the first one is scrolled into view and takes focus, so the blocked plan is the one being answered.
import { useEffect } from "react";
import type { Plan } from "../api/types";
import { AskCard } from "./AskCard";
import { asksOf } from "./question";
import { useSettled } from "./asks";
import type { SendCommand } from "./support";

export interface NeedsYouProps {
  plans: Plan[];
  onCommand: SendCommand;
  /** The plan whose Unblock was clicked last, or null: its open questions lead the rail, ringed. */
  spotlight?: string | null;
}

export function NeedsYou({ plans, onCommand, spotlight = null }: NeedsYouProps) {
  const settled = useSettled();
  const done = new Set(settled.map((s) => s.id));
  const all = asksOf(plans);
  const waiting = all.filter((a) => !done.has(a.id) && !(a.kind === "question" && a.question.held));
  const spotlit = (a: { plan: Plan }) => a.plan.ordinal === spotlight;
  const open = [...waiting.filter(spotlit), ...waiting.filter((a) => !spotlit(a))];
  // Each click on Unblock brings the first of that plan's cards into view and hands it focus: the answer box when
  // the question wants words, the first choice otherwise. jsdom has no scrollIntoView, hence the optional call.
  useEffect(() => {
    if (!spotlight) return;
    const card = document.querySelector<HTMLElement>(`.asks .ask.is-spotlit`);
    card?.scrollIntoView?.({ block: "nearest" });
    card?.querySelector<HTMLElement>("textarea, button")?.focus({ preventScroll: true });
  }, [spotlight]);
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
            {open.map((ask) => <AskCard key={ask.id} ask={ask} variant="rail" onCommand={onCommand} spotlit={spotlit(ask)} />)}
            {settledCards.map((ask) => "kind" in ask
              ? <AskCard key={ask.id} ask={ask} variant="rail" onCommand={onCommand} />
              : <div key={ask.id} className="ask is-done" data-ask={ask.id}><p className="ask-done">{ask.note}</p></div>)}
          </>
        )}
      </div>
    </aside>
  );
}
