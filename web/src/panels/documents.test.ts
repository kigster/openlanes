import { describe, expect, it } from "vitest";
import { DOCUMENT_LABELS, documentsOf } from "./documents";

describe("documentsOf", () => {
  it("returns labels in display order whatever order the server listed", () => {
    expect(documentsOf(["pull-requests.md", "plan.md", "blocked.md", "spec.md"]).map((d) => d.label))
      .toEqual(["Specification", "Plan", "Blocked", "Pull requests"]);
  });

  it("puts the Specification first when the plan has it", () => {
    expect(documentsOf(["design.md", "spec.md"])[0]).toEqual({ name: "spec.md", label: "Specification" });
  });

  it("drops names it has no label for", () => {
    expect(documentsOf(["notes.txt", "spec.md", "plan-backend.md"]).map((d) => d.name)).toEqual(["spec.md"]);
  });

  it("returns nothing for an empty list", () => {
    expect(documentsOf([])).toEqual([]);
  });

  it("labels every readable name once", () => {
    expect(new Set(DOCUMENT_LABELS.map((d) => d.name)).size).toBe(DOCUMENT_LABELS.length);
  });
});
