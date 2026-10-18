import { joinPlanFile, splitPlanFile } from "./planFile";

describe("splitPlanFile", () => {
  it("splits frontmatter from the body and joins them back byte for byte", () => {
    const text = "---\nlane: full\nresearch: false\n---\n# Title\n\nBody\n";
    const split = splitPlanFile(text);
    expect(split.frontmatter).toBe("---\nlane: full\nresearch: false\n---\n");
    expect(split.body).toBe("# Title\n\nBody\n");
    expect(joinPlanFile(split)).toBe(text);
  });

  it("keeps CRLF and trailing spaces", () => {
    const text = "---\r\nlane: full\r\n--- \r\nbody";
    expect(joinPlanFile(splitPlanFile(text))).toBe(text);
    expect(splitPlanFile(text).body).toBe("body");
  });

  it("treats a file with no frontmatter as all body", () => {
    expect(splitPlanFile("# Just a plan\n")).toEqual({ frontmatter: "", body: "# Just a plan\n" });
  });

  it("treats an unclosed block as all body", () => {
    expect(splitPlanFile("---\nlane: full\n")).toEqual({ frontmatter: "", body: "---\nlane: full\n" });
  });

  it("accepts a closing delimiter at the end of the file", () => {
    expect(splitPlanFile("---\na: 1\n---")).toEqual({ frontmatter: "---\na: 1\n---", body: "" });
  });
});
