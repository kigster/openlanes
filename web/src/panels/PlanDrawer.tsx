// The drawer a red pill opens beside the unblock widget: a dropdown of the plan's markdown files, and the one popup
// for whichever is chosen. Choosing another file replaces the popup, so there is never more than one.
import { useEffect, useId, useState } from "react";
import type { Plan } from "../api/types";
import { listPlanFiles } from "../api/planFiles";
import { PlanFilePopup } from "./PlanFilePopup";

/** The names the server lets a save through for; the server enforces it, this only hides a button it would refuse. */
const EDITABLE = ["spec.md", "plan.md"];

export interface PlanDrawerProps {
  /** The plan whose red pill was clicked, or null when the drawer is hidden. */
  plan: Plan | null;
}

export function PlanDrawer({ plan }: PlanDrawerProps) {
  const ordinal = plan?.ordinal ?? null;
  const [files, setFiles] = useState<string[] | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [chosen, setChosen] = useState<string | null>(null);
  const labelId = useId();

  useEffect(() => {
    setFiles(null);
    setFailure(null);
    setChosen(null);
    if (!ordinal) return;
    let live = true;
    listPlanFiles(ordinal).then(
      (names) => { if (live) setFiles(names); },
      (error: unknown) => { if (live) setFailure(error instanceof Error ? error.message : "Could not list the files."); },
    );
    return () => { live = false; };
  }, [ordinal]);

  if (!plan) return null;
  // The same data the board draws cars from, so the page and the server's live-car refusal cannot disagree.
  const live = plan.cars.length > 0;
  return (
    <section className="plan-drawer" aria-labelledby={labelId}>
      <h2 id={labelId}>Files of {plan.ordinal}</h2>
      {failure && <span role="alert" className="plan-file-error">{failure}</span>}
      {files && files.length === 0 && <span>No markdown files in this plan</span>}
      {files && files.length > 0 && (
        <select aria-label="Plan file" value={chosen ?? ""} onChange={(e) => setChosen(e.target.value || null)}>
          <option value="">Choose a file…</option>
          {files.map((name) => <option key={name} value={name}>{name}</option>)}
        </select>
      )}
      {chosen && (
        <PlanFilePopup
          key={chosen}
          ordinal={plan.ordinal}
          name={chosen}
          editable={!live && EDITABLE.includes(chosen)}
          onClose={() => setChosen(null)}
        />
      )}
    </section>
  );
}
