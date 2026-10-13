// The header's commands and the drawer: adding a plan, stopping everything here, switching a model, the machine tab.
import { MODAL } from "../support/selectors";

describe("the controls", () => {
  beforeEach(() => cy.openBoard());

  it("adds an existing plan from Action, Choose an existing plan", () => {
    cy.contains("button", "Action").click();
    cy.contains('[role="menuitem"]', "Choose an existing plan").click();
    cy.contains('[role="menuitem"]', "013.00 Plain NNN plan numbers").click();
    cy.boardEventually((me) => me.plans.some((p) => p.ordinal === "013.00") && !me.backlog.some((p) => p.ordinal === "013.00"));
    cy.contains("Plain NNN plan numbers").should("be.visible");
  });

  it("stops all local agents after asking first", () => {
    cy.contains("button", "Stop All Local").click();
    cy.get(MODAL).invoke("text").should("match", /Are you sure you want to shut down \d+ agents currently working on \d+ plans/);
    cy.get(MODAL).contains("button", "Stop them").click();
    cy.get(MODAL).should("not.exist");
    cy.boardEventually((me) => me.run.status === "quitting" && me.plans.every((p) => p.cars.every((c) => c.state !== "running")));
  });

  it("cancels Stop All Local without stopping anything", () => {
    cy.contains("button", "Stop All Local").click();
    cy.get(MODAL).contains("button", "Cancel").click();
    cy.get(MODAL).should("not.exist");
    cy.request("/api/board").its("body.me.run.status").should("eq", "running");
  });

  it("switches an agent's model from its drawer", () => {
    cy.get('[data-car="005.00/hansolo-reviewer"] .car-open').click();
    cy.get(".drawer").should("contain", "hansolo-reviewer");
    cy.get(".drawer .model-trigger").click();
    cy.contains('[role="option"]', "Opus 5.5").click();
    cy.boardEventually((me) => me.plans.flatMap((p) => p.cars).find((c) => c.key === "005.00/hansolo-reviewer")?.model === "claude-opus-5-5");
    cy.get(".drawer .drawer-meta").should("contain", "Model Opus 5.5");
  });

  it("toggles the machine tab: first press shows that machine, the second shows every machine", () => {
    cy.contains(".tab-machine", "sam@ci-runner-2").click();
    cy.contains(".tab-machine", "sam@ci-runner-2").should("have.attr", "aria-selected", "true");
    cy.contains("button", "All machines").should("have.attr", "aria-pressed", "false");
    cy.contains(".tab-machine", "sam@ci-runner-2").click();
    cy.contains("button", "All machines").should("have.attr", "aria-pressed", "true");
  });
});
