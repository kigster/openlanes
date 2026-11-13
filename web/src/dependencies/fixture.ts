import type { DependencyGraph } from "../api/types";

/** A chain 001 → 002 → 003, a loner 004, and an archived 005, for the tests. */
export const graph: DependencyGraph = {
  states: [
    { key: "building", emoji: "🟡", name: "Building" },
    { key: "planned", emoji: "⭐️", name: "Planned" },
    { key: "approved", emoji: "✅", name: "Approved" },
  ],
  plans: [
    { ordinal: "001.00", title: "First", state: "building", summary: "The first plan.", archived: false },
    { ordinal: "002.00", title: "Second", state: "planned", summary: null, archived: false },
    { ordinal: "003.00", title: "Third", state: "building", summary: "Third summary.", archived: false },
    { ordinal: "004.00", title: "Loner", state: "building", summary: null, archived: false },
    { ordinal: "005.00", title: "Archived", state: "approved", summary: "Old.", archived: true },
  ],
  edges: [
    { from: "001.00", to: "002.00" },
    { from: "002.00", to: "003.00" },
  ],
};
