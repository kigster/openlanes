// Choosing the coding agent per phase in the new-idea dialog (plan 040, PR 3): the demo board probes claude and codex
// as available and pi as not, so pi is listed disabled with its reason, and a phase put on codex lands in spec.md
// `phases`, which the command the page sends carries.
import { MODAL } from "../support/selectors";

describe("the coding agent per phase", () => {
  beforeEach(() => {
    cy.openBoard();
    // No interviewer, whatever the machine running the specs has set: the idea goes straight to create_plans.
    cy.intercept("POST", "/api/interview", { questions: [] });
    cy.intercept("POST", "/api/commands").as("command");
    cy.contains("button", "Action").click();
    cy.contains('[role="menuitem"]', "New idea").click();
    cy.get(MODAL).contains("label", "Building").click();
  });

  it("lists an adapter that cannot take an agent disabled, with its reason", () => {
    cy.get(MODAL).find('select[aria-label="Adapter for build"] option')
      .contains("pi: no model provider signed in").should("be.disabled");
    cy.get(MODAL).should("contain", "Not available on this machine: pi: no model provider signed in");
  });

  it("creates a plan with its build phase on codex", () => {
    cy.get(MODAL).find('select[aria-label="Adapter for build"]').select("codex");
    cy.get(MODAL).find('select[aria-label="Model for build"]').should("not.be.disabled");
    cy.get(MODAL).find(".cm-content").click().type("Rename the flag", { delay: 0 });
    cy.get(MODAL).contains("button", "Break it into plans").click();
    cy.wait("@command").its("request.body").should("deep.include", { kind: "create_plans" })
      .its("payload.frontmatter.phases").should("deep.equal", { build: { adapter: "codex" } });
    cy.get(MODAL).should("not.exist");
    cy.boardEventually((me) => me.plans.some((p) => p.title === "Rename the flag"));
  });
});
