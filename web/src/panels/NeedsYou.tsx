// The right rail: every question waiting on a person. A held question leaves the rail; its solid
// red pill in the status bar is the way back to it. Unblock on a lane spotlights that plan's questions: they move
// to the front, the first one is scrolled into view and takes focus, so the blocked plan is the one being answered.
import { useCallback, useEffect } from "react";
import type { Plan } from "../api/types";
import { AskCard } from "./AskCard";
import { asksOf } from "./question";
import { useSettled } from "./asks";
import { useChime } from "./chime";
import type { SendCommand } from "./support";

export interface NeedsYouProps {
  plans: Plan[];
  onCommand: SendCommand;
  /** The plan whose Unblock was clicked last, or null: its open questions lead the rail, ringed. */
  spotlight?: string | null;
  /** `chime:` from .openlanes.yml, as the engine reports it; an older engine says nothing, which means on. */
  chime?: boolean;
  /** What makes the sound for a new question; the tests pass their own. */
  play?: (count: number) => void;
}

export function NeedsYou({ plans, onCommand, spotlight = null, chime: saved = true, play }: NeedsYouProps) {
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
  // What was answered this session, newest first, folded away under a toggle that starts closed: twenty lines of
  // "Answered a) to planner." pushed the open questions off the rail and said nothing about which plan each was for.
  const answered = [...settled].reverse();
  const saveChime = useCallback((on: boolean) => {
    void onCommand({ kind: "set_chime", plan: null, agent: null, payload: { on } });
  }, [onCommand]);
  const chime = useChime(open.map((a) => a.id), saved, saveChime, play);
  return (
    <aside className="rail" aria-labelledby="rail-title">
      <h2 id="rail-title">Needs you {open.length ? <span>({open.length})</span> : null}</h2>
      <label className="rail-chime">
        <input type="checkbox" checked={chime.on} onChange={(e) => chime.toggle(e.target.checked)} />
        Ding when a question needs you
      </label>
      <p className="rail-sub">Questions wait here until you answer them.</p>
      <div className="asks" tabIndex={0} aria-label="Requests waiting on you">
        {open.length === 0 ? (
          <p className="empty">Nothing waiting on you. Agents will ask here.</p>
        ) : (
          open.map((ask) => <AskCard key={ask.id} ask={ask} variant="rail" onCommand={onCommand} spotlit={spotlit(ask)} />)
        )}
      </div>
      {answered.length > 0 && (
        <details className="answered">
          <summary>Answered <span>({answered.length})</span></summary>
          <ul>
            {answered.map((s) => (
              <li key={s.id} className="ask is-done" data-ask={s.id}>
                {/* The request's id opens with its plan, "040.00/X3": the note alone never said which plan it was for. */}
                <span className="answered-plan">{s.id.split("/")[0]}</span>
                <span className="ask-done">{s.note}</span>
              </li>
            ))}
          </ul>
        </details>
      )}
    </aside>
  );
}
