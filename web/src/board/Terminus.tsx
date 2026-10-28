import type { PullRequest, ReviewVote } from "../api/types";
import { ReviewVotes } from "./ReviewVotes";

const CI: Record<NonNullable<PullRequest["ci"]>, { cls: string; text: string }> = {
  passing: { cls: "ci-pass", text: "CI passing" },
  pending: { cls: "ci-run", text: "CI running" },
  failing: { cls: "ci-fail", text: "CI failing" },
};

const CHIP: Record<PullRequest["state"], { cls: string; text: string }> = {
  open: { cls: "chip-progress", text: "review-in-progress" },
  approved: { cls: "chip-approved", text: "approved" },
  merged: { cls: "chip-merged", text: "merged" },
  rejected: { cls: "chip-rejected", text: "rejected" },
  closed: { cls: "", text: "closed" },
};

/**
 * The PR at the end of a plan's line: its number as a link to GitHub (the URL comes from the board, never assembled
 * here), the CI result, the review label, and each reviewer's verdict with its coding agent's mark. A merged PR drops
 * CI: the plan is complete.
 */
export function Terminus({ pr, reviews }: { pr: PullRequest; reviews?: ReviewVote[] }) {
  const merged = pr.state === "merged";
  const ci = !merged && pr.ci ? CI[pr.ci] : null;
  const chip = CHIP[pr.state];
  return (
    <div className="terminus">
      <a className={`pr-link${merged ? " is-merged" : ""}`} href={pr.url} target="_blank" rel="noopener noreferrer">
        PR #{pr.number}
        <span className="sr-only"> (opens GitHub in a new tab)</span>
      </a>
      {ci && <span className={ci.cls}>{ci.text}</span>}
      <span className={`chip ${chip.cls}`.trim()}>{chip.text}</span>
      <ReviewVotes reviews={reviews} />
    </div>
  );
}
