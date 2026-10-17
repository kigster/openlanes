// The demo's fanned-out car (a 12-tick cycle: 3, 1, 0 sub-agents) draws one line per sub-agent; every other car stays plain.
const FANNED = '[data-car="001.00/rey-frontend"]';

describe("sub-agent lines on the tile", () => {
  beforeEach(() => cy.openBoard());

  it("shows 3 lines and the label while the demo fans out, then none", () => {
    cy.get(FANNED, { timeout: 30000 }).should("have.attr", "aria-label", "3 sub-agents running");
    cy.get(`${FANNED} .car-stack-line`).should("have.length", 3);
    cy.get(FANNED, { timeout: 30000 }).should("not.have.attr", "aria-label");
    cy.get(`${FANNED} .car-stack-line`).should("have.length", 0);
  });

  it("draws no lines on any other car", () => {
    cy.get(".car").not(FANNED).should("have.length.greaterThan", 0).each(($car) => {
      expect($car.find(".car-stack-line")).to.have.length(0);
    });
  });
});
