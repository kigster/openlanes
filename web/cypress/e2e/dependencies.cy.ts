import type { DependencyGraph } from "../../src/api/types";

// The Plan dependencies page against the real server and whatever .plans it serves, nothing stubbed. Expectations are
// read from GET /api/dependencies itself, so the spec holds for the demo's tree and for a fixture tree alike.
describe("plan dependencies", () => {
  const graph = () => cy.request<DependencyGraph>("/api/dependencies").its("body");

  beforeEach(() => {
    cy.window().then(w => w.localStorage.clear());
    cy.visit("/dependencies");
  });

  it("switches between the pages with no reload, and a refresh stays put", () => {
    cy.visit("/");
    cy.window().then(w => ((w as unknown as { marker: number }).marker = 1));
    cy.contains(".page-nav a", "Plan dependencies").click();
    cy.location("pathname").should("eq", "/dependencies");
    cy.window().its("marker").should("eq", 1); // the same document: no reload
    cy.contains(".page-nav a", "Board").click();
    cy.location("pathname").should("eq", "/");
    cy.contains(".page-nav a", "Plan dependencies").click();
    cy.reload();
    cy.location("pathname").should("eq", "/dependencies");
    cy.get(".dep-canvas, .dep-empty").should("exist");
  });

  it("draws one box per plan and one arrow per edge among the checked states", () => {
    graph().then(g => {
      const on = new Set(g.states.map(s => s.key).filter(k => !["approved", "deployed", "deferred", "abandoned", "discarded", "trashed"].includes(k)));
      const plans = g.plans.filter(p => on.has(p.state));
      const ids = new Set(plans.map(p => p.ordinal));
      const edges = g.edges.filter(e => ids.has(e.from) && ids.has(e.to));
      cy.get(".dep-node").should("have.length", plans.length);
      cy.get("path.dep-edge[data-from]").should("have.length", edges.length);
    });
  });

  it("brings archived plans in when Approved is checked", () => {
    graph().then(g => {
      const archived = g.plans.filter(p => p.archived);
      const done = g.states.find(s => s.key === "approved")!;
      cy.contains(".dep-filter label", done.name).find("input").check();
      archived.forEach(p => cy.get(`.dep-node[data-plan="${p.ordinal}"]`).should("exist"));
    });
  });

  it("filters a state out and shows its summary, or the fallback, on hover", () => {
    graph().then(g => {
      const first = g.plans.find(p => !["approved", "deployed", "deferred", "abandoned", "discarded", "trashed"].includes(p.state))!;
      const state = g.states.find(s => s.key === first.state)!;
      cy.get(`.dep-node[data-plan="${first.ordinal}"]`).trigger("mouseover").trigger("pointermove");
      cy.get(".dep-tip").should("be.visible");
      cy.contains(".dep-filter label", state.name).find("input").uncheck();
      cy.get(`.dep-node[data-plan="${first.ordinal}"]`).should("not.exist");
    });
  });
});
