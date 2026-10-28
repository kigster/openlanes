import { render, screen } from "@testing-library/react";
import { axe } from "vitest-axe";
import type { ReviewVote } from "../api/types";
import { ADAPTER_MARKS, voteLabel } from "./model";
import { AdapterMark, ReviewVotes } from "./ReviewVotes";
import { Terminus } from "./Terminus";

const staff: ReviewVote = { agent: "staff-reviewer", adapter: "claude", verdict: "passed", vulnerability: false };
const security: ReviewVote = { agent: "security-reviewer", adapter: "codex", verdict: "rejected", vulnerability: true };
const design: ReviewVote = { agent: "design-reviewer", adapter: null, verdict: "slop", vulnerability: false };

describe("ReviewVotes (plan 031, V3)", () => {
  it("draws nothing before any reviewer has spoken", () => {
    expect(render(<ReviewVotes reviews={[]} />).container).toBeEmptyDOMElement();
    expect(render(<ReviewVotes />).container).toBeEmptyDOMElement();
  });

  it("puts each verdict beside its coding agent's letter, in the order given", async () => {
    const { container } = render(<ReviewVotes reviews={[staff, security]} />);
    const votes = [...container.querySelectorAll(".vote")];
    expect(votes.map(v => [v.querySelector(".adapter-mark")?.textContent, v.className])).toEqual([
      ["A", "vote vote-passed"],
      ["O", "vote vote-rejected"],
    ]);
    expect(votes[1]).toHaveTextContent("rejected 💣");
    expect(await axe(container)).toHaveNoViolations();
  });

  it("names the reviewer, its coding agent and its verdict in words", () => {
    render(<ReviewVotes reviews={[security]} />);
    expect(screen.getByRole("list", { name: "Reviewers' verdicts" })).toBeInTheDocument();
    expect(screen.getByText("security-reviewer on codex: rejected, a vulnerability")).toHaveClass("sr-only");
    expect(screen.getByTitle("security-reviewer on codex: rejected, a vulnerability")).toHaveClass("vote");
  });

  it("marks a vote whose coding agent is unknown with a question mark, and leaves it out of the words", () => {
    expect(voteLabel(design)).toBe("design-reviewer: slop");
    expect(render(<AdapterMark adapter={null} />).container.firstChild).toHaveClass("adapter-mark", "mark-unknown");
    expect(render(<AdapterMark adapter="someday" />).container).toHaveTextContent("?");
  });

  it("has a letter and a vendor for every coding agent openlanes ships", () => {
    expect(Object.keys(ADAPTER_MARKS).sort()).toEqual(["claude", "codex", "gemini", "grok", "pi"]);
  });

  it("sits in the terminus after the review label", () => {
    const pr = { number: 7, url: "https://github.com/example/repo/pull/7", state: "open" as const, ci: null, merged_at: null };
    const { container } = render(<Terminus pr={pr} reviews={[staff]} />);
    expect(container.querySelector(".chip + .review-votes")).not.toBeNull();
  });
});
