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
    cy.contains("button", "Stop Local Workers").click();
    cy.get(MODAL).invoke("text").should("match", /Are you sure you want to shut down \d+ agents currently working on \d+ plans/);
    cy.get(MODAL).contains("button", "Stop them").click();
    cy.get(MODAL).should("not.exist");
    cy.boardEventually((me) => me.run.status === "quitting" && me.plans.every((p) => p.cars.every((c) => c.state !== "running")));
  });

  it("cancels Stop Local Workers without stopping anything", () => {
    cy.contains("button", "Stop Local Workers").click();
    cy.get(MODAL).contains("button", "Cancel").click();
    cy.get(MODAL).should("not.exist");
    cy.request("/api/board").its("body.me.run.status").should("eq", "running");
  });

  it("switches an agent's model from its drawer", () => {
    cy.get('[data-car="005.00/staff-reviewer"] .car-open').click();
    cy.get(".drawer").should("contain", "staff-reviewer");
    cy.get(".drawer .model-trigger").click();
    cy.contains('[role="option"]', "Opus 5.5").click();
    cy.boardEventually((me) => me.plans.flatMap((p) => p.cars).find((c) => c.key === "005.00/staff-reviewer")?.model === "claude-opus-5-5");
    cy.get(".drawer .drawer-meta").should("contain", "Model Opus 5.5");
  });

  it("holds an agent from its drawer and shows the board heard it", () => {
    cy.get('[data-car="005.00/staff-reviewer"] .car-open').click();
    cy.get(".drawer").contains("button", "Action").click();
    cy.contains('[role="menuitem"]', "Hold for now").click();
    cy.get(".drawer .feedback").should("contain", "Asked to hold for now.");
    cy.boardEventually((me) => me.plans.flatMap((p) => p.cars).find((c) => c.key === "005.00/staff-reviewer")?.held === true);
    cy.get(".drawer .d-held").should("contain", "On hold.");
  });

  it("asks before stopping an agent, and stops nothing when cancelled", () => {
    cy.get('[data-car="005.00/staff-reviewer"] .car-open').click();
    cy.get(".drawer").contains("button", "Action").click();
    cy.contains('[role="menuitem"]', "Stop agent").click();
    cy.get(MODAL).should("contain", "Stop staff-reviewer?");
    cy.get(MODAL).contains("button", "Cancel").click();
    cy.get(MODAL).should("not.exist");
    cy.request("/api/board").its("body.me.plans").then((plans: { cars: { key: string; state: string }[] }[]) => {
      expect(plans.flatMap((p) => p.cars).find((c) => c.key === "005.00/staff-reviewer")?.state).to.eq("running");
    });
    cy.get(".drawer").contains("button", "Action").click();
    cy.contains('[role="menuitem"]', "Stop agent").click();
    cy.get(MODAL).contains("button", "Stop agent").click();
    cy.boardEventually((me) => me.plans.flatMap((p) => p.cars).find((c) => c.key === "005.00/staff-reviewer")?.state !== "running");
  });

  it("shows dollars spent on a plan's row and in its agent's drawer", () => {
    cy.get('[data-plan="005.00"] .plan-cost').invoke("text").should("match", /\$\d+\.\d\d/);
    cy.get('[data-car="005.00/staff-reviewer"] .car-open').click();
    cy.contains(".drawer .drawer-stats div", "Cost").find("strong").invoke("text").should("match", /^\$\d+\.\d\d$/);
  });

  it("toggles the machine tab: first press shows that machine, the second shows every machine", () => {
    cy.contains(".tab-machine", "sam@ci-runner-2").click();
    cy.contains(".tab-machine", "sam@ci-runner-2").should("have.attr", "aria-selected", "true");
    cy.contains("button", "All Machines").should("have.attr", "aria-pressed", "false");
    cy.contains(".tab-machine", "sam@ci-runner-2").click();
    cy.contains("button", "All Machines").should("have.attr", "aria-pressed", "true");
  });

  // The pills fold behind Menu on a narrow page, and the status line moves above the tabs.
  it("folds the pills behind Menu when the page is narrow", () => {
    cy.contains("button", "Menu").should("not.be.visible");
    // Wide, the status line is beside the tabs: it reaches below their top edge.
    cy.get(".statusline").then(($line) => expect($line[0].getBoundingClientRect().bottom).to.be.greaterThan(Cypress.$(".tab")[0].getBoundingClientRect().top + 10));
    cy.viewport(900, 900);
    cy.contains("button", "All Machines").should("not.be.visible");
    cy.contains("button", "Menu").click().should("have.attr", "aria-expanded", "true");
    cy.contains("button", "All Machines").should("be.visible").click().should("have.attr", "aria-pressed", "true");
    cy.contains("button", "Stop Local Workers").should("be.visible");
    cy.get("body").type("{esc}");
    cy.contains("button", "All Machines").should("not.be.visible");
    cy.get(".statusline").then(($line) => expect($line[0].getBoundingClientRect().bottom).to.be.at.most(Cypress.$(".tab")[0].getBoundingClientRect().top + 1));
  });
});
