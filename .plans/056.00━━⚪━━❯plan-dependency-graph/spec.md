---
created: 2026-10-27
starts: planning
---

# Plan Dependencies

Source: the user, 2026-10-27. Split on 2026-10-27 (S6): the settings page is plan 058, its backend plan 057.

## What we are trying to achieve

1. **A top-level nav in the control room**, fixed to the top and shared by every page: `Board | Plan dependencies | Project settings`. The board stays as it is, its own tabs (logs, apps, test runs, machines) included.
2. **The Plan dependencies page**, a graph of the plans, drawn with React Flow (`@xyflow/react`, MIT): one box per plan, an arrow for each `depends_on:` edge, laid out automatically from dependency to dependent, left to right. Boxes can be dragged; zoom and pan work.
3. **Each box shows the plan's number and title** (and its state, as the board draws it). Hovering a box, or clicking it to pin it, shows a paragraph that summarizes the feature.
4. **A checkbox per state above the graph** hides or shows the plans in that state. Unchecking Done shows everything not yet done; unchecking everything but the first state shows only the brand-new plans.

## Why it matters

Plans wait on each other, and today the only view of that is `depends_on:` read file by file, or the "queued behind NNN.MM" note on the board. A graph shows at a glance what blocks what, which chains are long, and what can start now.

## Decisions (2026-10-27)

- **G1, library:** React Flow (`@xyflow/react`), with an automatic layered layout (dagre or elkjs; planning picks one).
- **G2, pages:** one React SPA, not separate pages: a nav fixed to the top, `Board | Plan dependencies | Project settings`, switching pages without a reload. Each page has a path (`/`, `/dependencies`, `/settings`) so a link or a refresh lands on it; the server already sends `index.html` for any path that is not an asset (`Web::App`, `get "/*"`). The board is unchanged. This plan builds the nav with the board and Plan dependencies; plan 058 adds Project settings to it.
- **G3, the summary:** a new optional `summary:` key in spec.md frontmatter, one paragraph. The spec agent writes it when it fills a spec in, and a person may edit it. A plan without one falls back to the first prose paragraph of spec.md's "What we are trying to achieve".
- **G4, the filter:** one checkbox per state, in the order `STATUSES` defines them. On first open every state is checked but Done and Abandoned. The choice is remembered per browser (localStorage, per project).
- **G5, dragging:** positions are not remembered. Every reload, and every filter change, lays the graph out again.
- **G6, hidden plans in a chain:** when the filter hides a plan between two visible ones (C depends on B depends on A, B hidden), A → C is drawn as a dashed arrow whose tooltip names the hidden plans it passes through.
- **G7, nice to have (not required):** a dashed outline around each DAG, each connected group of plans, so separate dependency groups read as separate at a glance. Planning decides whether it fits this plan or follows it.

## What already exists

- `Plans::Dependencies` reads every plan's `depends_on:` (who waits for whom, and the reverse).
- `Plans::Status` `STATUSES`: each state's key, emoji and order, which the filter and the boxes read rather than copying.
- The control room: React 19 and Vite, Radix tooltips, the board in `web/src/board/`, the board snapshot published over SSE.

## How to tell it's working?

- The nav switches between the pages without a reload, the URL says which page is open, and a refresh stays on it.
- Every plan in `.plans` (archive included, when Done is checked) has one box and every `depends_on:` edge one arrow.
- Unchecking a state removes its boxes; a hidden plan in a chain leaves a dashed bridge with the right tooltip.
- Hover and click show the `summary:` paragraph, or the fallback.
- `summary:` is validated as text in spec.md frontmatter, and `openlanes docs` lists it.
- Component tests for the filter and the bridging, and a Cypress test that opens the page, filters, and hovers a box.

