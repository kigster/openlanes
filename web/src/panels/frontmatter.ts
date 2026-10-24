// The frontmatter the idea dialog sets for every plan its idea becomes; Plans::Spec owns the vocabulary.
export interface IdeaFrontmatter {
  starts: "research" | "planning" | "building";
  research: boolean;
  frontend: "auto" | "true" | "false";
  depth: "auto" | "fast" | "medium" | "deep";
}

export const IDEA_DEFAULTS: IdeaFrontmatter = { starts: "research", research: false, frontend: "auto", depth: "auto" };
