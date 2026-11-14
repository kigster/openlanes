// The plan documents the lane dropdown offers, under English labels instead of file names. One row here and one name in
// PlanFiles::READABLE (lib/openlanes/web/plan_files.rb) is all a new document takes.
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

/** The documents the plan has, in label order (Specification first); names the table does not know are dropped. */
export function documentsOf(files: string[]): Document[] {
  const have = new Set(files);
  return DOCUMENT_LABELS.filter((doc) => have.has(doc.name));
}
