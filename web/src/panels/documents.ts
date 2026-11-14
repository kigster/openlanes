// The plan documents the lane dropdown offers, under English labels instead of file names. The server's list
// (PlanFiles::READABLE, lib/openlanes/web/plan_files.rb) decides which documents exist and in what order; this table only
// supplies nicer labels, and a name it lacks gets its file name humanized rather than being dropped.
export interface Document {
  name: string;
  label: string;
}

export const DOCUMENT_LABELS: ReadonlyArray<Document> = [
  { name: "spec.md", label: "Specification" },
  { name: "plan.md", label: "Plan" },
  { name: "contract.md", label: "Contract" },
  { name: "research.md", label: "Research" },
  { name: "design.md", label: "Design" },
  { name: "blocked.md", label: "Blocked" },
  { name: "pull-requests.md", label: "Pull requests" },
];

const humanize = (name: string): string => {
  const words = name.replace(/\.md$/, "").replace(/[-_]+/g, " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
};

/** The documents the plan has, in the order the server listed them; an unlabelled name is labelled from its file name. */
export function documentsOf(files: string[]): Document[] {
  return files.map((name) => DOCUMENT_LABELS.find((doc) => doc.name === name) ?? { name, label: humanize(name) });
}
