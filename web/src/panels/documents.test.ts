import { describe, expect, it } from "vitest";
import { DOCUMENT_LABELS, documentsOf } from "./documents";

describe("documentsOf", () => {
  it("keeps the order the server listed", () => {
    expect(documentsOf(["spec.md", "plan.md", "blocked.md", "pull-requests.md"]).map((d) => d.label))
      .toEqual(["Specification", "Plan", "Blocked", "Pull requests"]);
  });

  it("labels a name the table lacks from its file name instead of dropping it", () => {
    expect(documentsOf(["spec.md", "verdict.md", "code-review_notes.md"]))
      .toEqual([
        { name: "spec.md", label: "Specification" },
        { name: "verdict.md", label: "Verdict" },
        { name: "code-review_notes.md", label: "Code review notes" },
      ]);
  });

  it("returns nothing for an empty list", () => {
    expect(documentsOf([])).toEqual([]);
  });

  it("labels every readable name once", () => {
    expect(new Set(DOCUMENT_LABELS.map((d) => d.name)).size).toBe(DOCUMENT_LABELS.length);
  });
});
