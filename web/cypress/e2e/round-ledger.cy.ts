// Plan 065: the page shows the CLI the engine paused after an authentication failure, and the round the ledger gave an agent.
// The three choices of a request for more rounds are covered in NeedsYou.test.tsx and AgentDrawer.test.tsx: the demo
// board has no plan free to carry one without changing every question count in the unit tests.
describe("the round ledger", () => {
  beforeEach(() => cy.openBoard());

  it("names the paused CLI and why, and says no round is spent meanwhile", () => {
    cy.get(".paused-clis").should("be.visible").within(() => {
      cy.contains("claude paused");
      cy.get('[data-adapter="claude"]').should("contain", "OAuth session expired");
      cy.contains("no round is spent");
    });
  });

  it("shows the round the agent was told in its drawer", () => {
    cy.get('[data-car="005.00/staff-reviewer"] .car-open').click();
    cy.get(".drawer [data-round]").invoke("text").should("match", /^Round \d+ of \d+\.$/);
  });
});
