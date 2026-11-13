import type { SettingsDocument } from "../api/types";

/** A small schema in the shape GET /api/settings serves: scalars, a section, and `commands` with two sub-sections. */
export const doc: SettingsDocument = {
  schema: {
    type: "object",
    properties: {
      project: { type: ["string", "null"], description: "The project name" },
      frontend: { type: ["boolean", "null"], description: "Build a front end", default: false },
      jobs: { type: ["integer", "null"], description: "Plans at once", minimum: 1 },
      ratio: { type: ["number", "null"], description: "A ratio" },
      tags: { type: ["array", "null"], description: "Some tags" },
      merge: {
        type: ["object", "null"],
        description: "Merging",
        properties: {
          by: { type: ["string", "null"], description: "Who merges", enum: ["human", "auto", null] },
          nested: { type: ["object", "null"], properties: { depth: { type: ["integer", "null"], description: "Depth" } } },
        },
      },
      commands: {
        type: "object",
        description: "Per-command defaults",
        properties: {
          run: { type: "object", properties: { fast: { type: "boolean", description: "Go fast" } } },
          "api docs": { type: "object", properties: {} },
        },
      },
    },
  },
  keys: ["project", "frontend", "jobs", "ratio", "tags", "merge", "commands"],
  values: { project: "demo", jobs: 2, merge: { by: "human" } },
  defaults: { frontend: false, jobs: 4, merge: { by: null } },
  etag: "e1",
  branch: "main",
};
