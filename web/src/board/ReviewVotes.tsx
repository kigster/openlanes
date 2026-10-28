import type { ReviewVote } from "../api/types";
import { ADAPTER_MARKS, voteLabel } from "./model";

/** The coding agent's mark. Decorative: the vote beside it names the agent in words. */
export function AdapterMark({ adapter }: { adapter: string | null }) {
  const mark = adapter ? ADAPTER_MARKS[adapter] : undefined;
  return (
    <span className={`adapter-mark mark-${adapter ?? "unknown"}`} aria-hidden="true">
      {mark?.letter ?? "?"}
    </span>
  );
}

/** The latest review round's verdicts at the end of the plan's line, each beside the mark of the agent that gave it. */
export function ReviewVotes({ reviews }: { reviews?: ReviewVote[] }) {
  if (!reviews?.length) return null;
  return (
    <ul className="review-votes" aria-label="Reviewers' verdicts">
      {reviews.map(vote => (
        <li key={vote.agent} className={`vote vote-${vote.verdict}`} title={voteLabel(vote)}>
          <AdapterMark adapter={vote.adapter} />
          <span aria-hidden="true">{vote.verdict}{vote.vulnerability ? " 💣" : ""}</span>
          <span className="sr-only">{voteLabel(vote)}</span>
        </li>
      ))}
    </ul>
  );
}
