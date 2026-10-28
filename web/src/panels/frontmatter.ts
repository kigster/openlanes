import type { Snapshot } from "../api/types";

// The frontmatter the idea dialog sets for every plan its idea becomes; Plans::Spec owns the vocabulary.
export interface IdeaFrontmatter {
  starts: "research" | "planning" | "building";
  research: boolean;
  frontend: "auto" | "true" | "false";
  depth: "auto" | "fast" | "medium" | "deep";
  /** spec.md `phases:` (plan 040, D12): an adapter and a model per phase; "" leaves it to the phase's agents. */
  phases: Record<string, PhaseChoice>;
}

export interface PhaseChoice {
  adapter: string;
  model: string;
}

export const IDEA_DEFAULTS: IdeaFrontmatter = { starts: "research", research: false, frontend: "auto", depth: "auto", phases: {} };

/** "Agent's default" in a phase row: nothing is written for it. */
export const DEFAULT = "";
export const NONE: PhaseChoice = { adapter: DEFAULT, model: DEFAULT };

/** What the rows are drawn from: the snapshot's probed adapters and the phases each starts walks. */
export type PhaseCatalog = Pick<Snapshot, "adapters" | "phases">;

/** The phases a plan with this form will walk: a phase whose agent the form switches off ("Front end: No") is left out. */
export const walked = (catalog: PhaseCatalog, fm: IdeaFrontmatter) =>
  catalog.phases[fm.starts].filter(row => !(row.toggle && fm[row.toggle as keyof IdeaFrontmatter] === "false"));

/** The rows' choices as spec.md `phases:`: only phases the plan walks, and only what was chosen. */
export function chosenPhases(catalog: PhaseCatalog, fm: IdeaFrontmatter): Record<string, Partial<PhaseChoice>> {
  const out: Record<string, Partial<PhaseChoice>> = {};
  for (const { phase } of walked(catalog, fm)) {
    const { adapter, model } = fm.phases[phase] ?? NONE;
    const kept = Object.fromEntries(Object.entries({ adapter, model }).filter(([, v]) => v !== DEFAULT));
    if (Object.keys(kept).length > 0) out[phase] = kept;
  }
  return out;
}
