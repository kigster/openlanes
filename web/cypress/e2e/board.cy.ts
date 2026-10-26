import type { Result } from "axe-core";

// The board as the demo publishes it: this machine's plans, the other machine's tab, and the page staying live.
describe("the board", () => {
  beforeEach(() => cy.openBoard());

  it("loads this machine's plans with their agents", () => {
    cy.contains("Clean agent boundaries and transitions");
    // The review cars may sit past the viewport edge, so scroll to them before asserting.
    cy.get('[data-car="005.00/staff-reviewer"]').scrollIntoView().should("be.visible");
    cy.get(".tab-machine").should("contain", "sam@ci-runner-2");
  });

  it("moves: the demo's tokens grow and the page follows", () => {
    cy.get(".topbar-stat").eq(2).invoke("text").then((before) => {
      cy.get(".topbar-stat", { timeout: 10000 }).eq(2).should(($stat) => {
        expect($stat.text()).not.to.eq(before);
      });
    });
  });

  // The whole page, in both themes: tinted chips and tabs are where soft text loses contrast first.
  for (const theme of ["light", "dark"]) {
    it(`has no serious accessibility violations in the ${theme} theme`, () => {
      cy.document().then((doc) => doc.documentElement.setAttribute("data-theme", theme));
      cy.injectAxe();
      cy.checkA11y(undefined, { includedImpacts: ["serious", "critical"] }, report);
    });
  }

  // The pills' time sits on a tinted plate in every state, so contrast is checked in both themes.
  for (const theme of ["light", "dark"]) {
    it(`has accessible status bar pills in the ${theme} theme`, () => {
      cy.document().then((doc) => doc.documentElement.setAttribute("data-theme", theme));
      cy.injectAxe();
      cy.checkA11y(".statusbar", { includedImpacts: ["serious", "critical"] }, report);
    });
  }
});

// Each violation and the elements it was found on, in the terminal, so a CI log says what to fix.
function report(violations: Result[]) {
  const lines = violations.map((v) => [`${v.id} (${v.impact}): ${v.help}`, ...v.nodes.map((n) => `  ${n.target.join(" ")}: ${n.failureSummary ?? ""}`)]);
  cy.task("log", lines.flat().join("\n"));
}
