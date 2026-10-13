import type { Result } from "axe-core";
import { MODAL } from "../support/selectors";

// The chat between machines (plan 006), against the demo: its other machine is pretend, so nothing listens for it.
// That is the case the spec covers end to end here: a chat starts, a message goes round, and the invite says at once
// that nobody answered. Two real machines chatting are covered by the Ruby suite's two hubs on one Redis.
describe("the chat between machines", () => {
  beforeEach(() => cy.openBoard());

  it("starts a chat from a machine's ▾, sends a message, and hears that nobody answered", () => {
    cy.get('button[aria-label="Chat with sam@ci-runner-2"]').click();
    cy.contains('[role="menuitem"]', "Start Chat").click();
    // The Name dialog is a modal; the chat panel is a non-modal dialog that stays in the DOM, so scope to MODAL.
    cy.get(MODAL).should("contain", "Chat with sam@ci-runner-2").find("#chat-name").clear().type("Dana{enter}");
    cy.get(MODAL).should("not.exist");
    cy.get("#chat").should("be.visible").and("have.attr", "data-dock", "left");
    cy.get("#chat h2").should("have.text", "Dana");
    cy.get("#chat").should("contain", "sam@ci-runner-2 did not answer");
    cy.get("#chat-input").type("see https://example.com{meta}{enter}");
    cy.get("#chat .chat-text a").should("have.attr", "href", "https://example.com");
    cy.injectAxe();
    const report = (violations: Result[]) =>
      cy.task("log", violations.map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(" ")).join(", ")}`).join("\n"));
    cy.checkA11y("#chat", { includedImpacts: ["serious", "critical"] }, report);
    cy.get('button[aria-label="Chat with sam@ci-runner-2"]').click();
    cy.contains('[role="menuitem"]', "Stop Chat").click();
    cy.get("#chat").should("not.exist");
  });

  it("opens the same menu on a right-click on the tab", () => {
    cy.contains(".tab-machine", "sam@ci-runner-2").rightclick();
    cy.contains('[role="menuitem"]', "Start Chat").should("be.visible");
  });
});
