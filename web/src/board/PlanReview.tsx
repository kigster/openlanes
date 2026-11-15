// A plan's pull request in review: the diff stat, the patch behind a toggle, and each reviewer finding with Accept and
// Strike. A ruling goes out as `rule_finding`, then the review is read again, so the page shows what the engine kept.
import { useId, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { reviewKey, usePlanReview } from "../api/planReview";
import type { Plan, Reply, ReviewFinding } from "../api/types";
import { useCommand } from "../panels/command";
import { Feedback } from "../panels/feedback";
import type { SendCommand } from "../panels/support";

const where = (f: ReviewFinding) => (f.file ? ` ${f.file}${f.line ? `:${f.line}` : ""}` : "");

function Finding({ finding, busy, onRule }: { finding: ReviewFinding; busy: boolean; onRule: (id: string, verdict: "accept" | "strike") => void }) {
  const ruled = finding.ruling;
  return (
    <li className={`finding${ruled ? ` is-${ruled}` : ""}`}>
      <p>
        <strong>{finding.id}</strong> {finding.reviewer}
        {finding.severity ? ` (${finding.severity})` : ""}
        <span className="finding-where">{where(finding)}</span>
      </p>
      <p>{finding.text}</p>
      <div className="finding-actions">
        <button type="button" className="btn" aria-pressed={ruled === "accept"} disabled={busy} onClick={() => onRule(finding.id, "accept")}>Accept<span className="sr-only"> {finding.id}</span></button>
        <button type="button" className="btn" aria-pressed={ruled === "strike"} disabled={busy} onClick={() => onRule(finding.id, "strike")}>Strike<span className="sr-only"> {finding.id}</span></button>
        {ruled && <span className="finding-ruling">{ruled === "strike" ? "Struck" : "Accepted"}</span>}
      </div>
    </li>
  );
}

export function PlanReview({ plan, onCommand }: { plan: Plan; onCommand: SendCommand }) {
  const [open, setOpen] = useState(false);
  const [patch, setPatch] = useState(false);
  const ids = { body: useId(), patch: useId() };
  const client = useQueryClient();
  const review = usePlanReview(plan.ordinal, open);
  const command = useCommand(onCommand);

  const rule = async (finding: string, verdict: "accept" | "strike") => {
    const reply: Reply | null = await command.send(
      { kind: "rule_finding", plan: plan.ordinal, agent: null, payload: { finding, verdict } },
      r => r.reason ?? `${finding} ${verdict}`,
    );
    if (reply && reply.status !== "refused") await client.invalidateQueries({ queryKey: reviewKey(plan.ordinal) });
  };

  const data = review.data;
  return (
    <div className="plan-review">
      <button type="button" className="btn btn-quiet" aria-expanded={open} aria-controls={ids.body} onClick={() => setOpen(!open)}>
        {open ? "Hide review" : "Review"}
      </button>
      <div id={ids.body} hidden={!open}>
        {review.isPending && open && <p>Loading the review…</p>}
        {review.isError && <p className="feedback is-refused">The review could not be read.</p>}
        {data && (
          <>
            <pre className="review-stat">{data.diff.stat || "No changes against the base."}</pre>
            {data.diff.patch && (
              <>
                <button type="button" className="btn btn-quiet" aria-expanded={patch} aria-controls={ids.patch} onClick={() => setPatch(!patch)}>
                  {patch ? "Hide patch" : "Show patch"}
                </button>
                <pre id={ids.patch} className="review-patch" hidden={!patch}>{data.diff.patch}</pre>
                {data.diff.truncated && <p className="drawer-meta">The patch is cut short.</p>}
              </>
            )}
            {data.findings.length === 0 ? (
              <p>No findings.</p>
            ) : (
              <ul className="findings" aria-label={`Findings on ${plan.ordinal}`}>
                {data.findings.map(f => <Finding key={f.id} finding={f} busy={command.pending} onRule={rule} />)}
              </ul>
            )}
          </>
        )}
        <Feedback outcome={command.outcome?.tone === "refused" ? command.outcome : null} announced={command.announced} />
      </div>
    </div>
  );
}
