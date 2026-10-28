// Shared commands for the control room's end-to-end specs. Every spec starts from the demo's fixture board, so specs
// can run in any order and again without a restart of the server.
import "cypress-axe";

interface Snapshot {
  plans: Array<{ ordinal: string; title: string; questions: Array<{ number: number; held: boolean }>; cars: Array<{ key: string; model: string; state: string }> }>;
  backlog: Array<{ ordinal: string }>;
  run: { status: string };
}

interface Board {
  me: Snapshot | null;
  others: Snapshot[];
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Cypress {
    interface Chainable {
      /** Puts the demo's board back to the fixture. */
      resetDemo(): Chainable<void>;
      /** Resets the demo, opens the page, and waits for the board to be live. */
      openBoard(): Chainable<void>;
      /** Polls GET /api/board until `check` holds for this node's snapshot, failing after `tries` seconds. */
      boardEventually(check: (me: Snapshot) => boolean, tries?: number): Chainable<void>;
    }
  }
}

Cypress.Commands.add("resetDemo", () => {
  cy.request<{ csrf: string }>("/api/session").then(({ body }) => {
    cy.request({ method: "POST", url: "/api/demo/reset", headers: { "X-CSRF-Token": body.csrf } });
  });
  // The reset lands on the demo's next tick, at most a second later.
  cy.boardEventually((me) => me.plans.some((p) => p.ordinal === "001.00" && p.questions.length === 1) && me.run.status === "running");
});

Cypress.Commands.add("openBoard", () => {
  cy.resetDemo();
  cy.visit("/");
  cy.contains(".node", "dana@studio-mini");
  cy.get("[data-car]").should("have.length.at.least", 3);
});

Cypress.Commands.add("boardEventually", (check: (me: Snapshot) => boolean, tries = 10) => {
  cy.request<Board>("/api/board").then(({ body }) => {
    if (body.me && check(body.me)) return;
    if (tries <= 0) throw new Error("the board never reached the expected state");
    cy.wait(1000, { log: false });
    cy.boardEventually(check, tries - 1);
  });
});

export {};
