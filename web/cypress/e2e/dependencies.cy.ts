import type { DependencyGraph } from "../../src/api/types";

// The Plan dependencies page against the real server and whatever .plans it serves, nothing stubbed. Expectations are
// read from GET /api/dependencies itself, so the spec holds for the demo's tree and for a fixture tree alike.
describe("plan dependencies", () => {
  const graph = () => cy.request<DependencyGraph>("/api/dependencies").its("body");
  // Off by default: the states the server flags archived, so this spec copies no list out of status.rb.
  const archived = (g: DependencyGraph) => new Set(g.states.filter(s => s.archived).map(s => s.key));

  // The legend, and the state checkboxes in it, are folded away until asked for.
  const legend = () => cy.contains("button", "States legend").click();

  beforeEach(() => {
    cy.window().then(w => w.localStorage.clear());
    cy.visit("/dependencies");
  });

  it("keeps the states legend folded until its button is pressed", () => {
    cy.contains("button", "States legend").should("have.attr", "aria-expanded", "false");
    cy.get(".dep-filter input[type=checkbox]").should("not.be.visible");
    legend();
    cy.contains("button", "States legend").should("have.attr", "aria-expanded", "true");
    cy.get(".dep-filter input[type=checkbox]").first().should("be.visible");
  });

  it("opens a plan's documents from its box", () => {
    cy.get("body").then($body => {
      if ($body.find(".dep-node").length === 0) return;
      cy.get(".dep-node-docs button").first().click({ force: true });
      cy.get('[role="menuitem"]').should("have.length.at.least", 1);
      cy.get("body").then($b => {
        if ($b.find('[role="menuitem"]:not([data-disabled])').length === 0) return; // a plan with no documents says so
        cy.get('[role="menuitem"]:not([data-disabled])').first().click();
        cy.get('[role="dialog"]').should("be.visible");
      });
    });
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
      const on = new Set(g.states.map(s => s.key).filter(k => !archived(g).has(k)));
      const plans = g.plans.filter(p => on.has(p.state));
      const ids = new Set(plans.map(p => p.ordinal));
      const edges = g.edges.filter(e => ids.has(e.from) && ids.has(e.to));
      cy.get(".dep-node").should("have.length", plans.length);
      cy.get("path.dep-edge[data-from]").should("have.length", edges.length);
    });
  });

  it("re-arranges the graph from the layout picker, keeps every box and arrow, and remembers the pick", () => {
    const count = (selector: string) => cy.get("body").then($b => $b.find(selector).length);
    const corners = () => cy.get(".react-flow__node").then($n => $n.toArray().map(n => n.style.transform).join("|"));
    cy.get(".dep-canvas, .dep-empty").should("exist");
    cy.get("body").then($body => {
      if ($body.find(".dep-canvas").length === 0) return; // an empty tree has nothing to arrange
      cy.get('.dep-layout input[value="adaptive"]').should("be.checked");
      count(".dep-node").then(nodes =>
        count("path.dep-edge").then(arrows =>
          corners().then(before => {
            ["down", "circular", "grid", "right"].forEach(kind => {
              cy.get(`.dep-layout input[value="${kind}"]`).check({ force: true });
              cy.get(".dep-canvas").should("have.attr", "data-layout", kind);
              cy.get(".dep-node").should("have.length", nodes);
              cy.get("path.dep-edge").should("have.length", arrows);
              // Two unlinked plans sit side by side in most arrangements; on a ring they never do.
              if (nodes > 1 && kind === "circular") corners().should("not.eq", before);
            });
          }),
        ),
      );
      cy.get('.dep-layout input[value="circular"]').check({ force: true });
      cy.reload();
      cy.get('.dep-layout input[value="circular"]').should("be.checked");
      cy.get(".dep-canvas").should("have.attr", "data-layout", "circular");
    });
  });

  it("brings archived plans in when Approved is checked", () => {
    graph().then(g => {
      const gone = g.plans.filter(p => p.archived);
      const done = g.states.find(s => s.key === "approved")!;
      expect(done.archived, "approved is an archived state").to.eq(true);
      legend();
      cy.contains(".dep-filter label", done.name).find("input").check();
      gone.forEach(p => cy.get(`.dep-node[data-plan="${p.ordinal}"]`).should("exist"));
    });
  });

  it("filters a state out and shows its summary, or the fallback, on hover", () => {
    graph().then(g => {
      const first = g.plans.find(p => !archived(g).has(p.state))!;
      const state = g.states.find(s => s.key === first.state)!;
      const box = `.dep-node[data-plan="${first.ordinal}"]`;
      // React hears pointerenter through pointerover; a real mouse sends both.
      cy.get(box).trigger("pointerover", { pointerType: "mouse", force: true });
      cy.get(".dep-tip").should("be.visible").and("contain.text", first.summary?.trim() || "No summary has been written for this plan yet.");
      cy.get(box).trigger("pointerout", { pointerType: "mouse", force: true });
      cy.get(".dep-tip").should("not.exist");
      legend();
      cy.contains(".dep-filter label", state.name).find("input").uncheck();
      cy.get(box).should("not.exist");
      // Hiding a state may leave a dashed bridge over its plans; where one is drawn, hovering it names them.
      cy.get("body").then($body => {
        if ($body.find(".dep-bridge").length === 0) return;
        cy.get(".dep-bridge").first().trigger("pointerover", { pointerType: "mouse", force: true });
        cy.get(".dep-tip").should("be.visible").and("contain.text", "Passes through hidden");
      });
    });
  });
});
