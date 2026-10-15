import type { Result } from "axe-core";
import type { PeerEvent } from "../peer";
import { MODAL } from "../support/selectors";

// The chat between machines (plan 006), against the demo, nothing stubbed. Two machines are in it: the demo's own,
// whose page Cypress drives, and a second `openlanes web --demo --identity demo@second-machine` that `just web-e2e`
// starts on the peer port, on the same Redis and repository. Cypress plays that machine's page through cy.request,
// with a task holding its event stream open so its server counts the page as present.
const PEER: string = Cypress.env("peer");
const PEER_LABEL = "demo@second-machine";

interface PeerChat {
  invites: Array<{ id: string; from: { name: string } }>;
}

/** POSTs a chat verb to the second machine's server, under its CSRF token. */
const peerSays = (csrf: string, verb: string, body: Record<string, unknown>) =>
  cy.request({ method: "POST", url: `${PEER}/api/chat/${verb}`, headers: { "X-CSRF-Token": csrf }, body }).its("status").should("eq", 202);

/** Polls the second machine's `GET /api/chat` until the page has an invite, and yields its id. */
const inviteFor = (page: string, tries = 10): Cypress.Chainable<string> =>
  cy.request<PeerChat>(`${PEER}/api/chat?page=${page}`).then(({ body }) => {
    if (body.invites.length > 0) return cy.wrap(body.invites[0].id);
    if (tries <= 0) throw new Error(`${PEER_LABEL} never heard the invite`);
    cy.wait(500, { log: false });
    return inviteFor(page, tries - 1);
  });

/** Polls the second page's relayed events until one matches, failing after `tries` half-seconds. */
const peerHears = (page: string, match: (e: PeerEvent) => boolean, tries = 16): Cypress.Chainable<PeerEvent> =>
  cy.task<PeerEvent[]>("peerEvents", page, { log: false }).then((events) => {
    const found = events.find(match);
    if (found) return cy.wrap(found);
    if (tries <= 0) throw new Error(`${PEER_LABEL}'s page never heard it`);
    cy.wait(500, { log: false });
    return peerHears(page, match, tries - 1);
  });

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

  describe("with a second machine", () => {
    // A fresh page id each run: a page that left keeps its id for the stream's grace period.
    const page = `peer-${Date.now()}`;

    afterEach(() => cy.task("peerClose", page));

    // Steps 1 to 4 of the integration scenario: start, the second machine joins, a message each way, it leaves.
    it("is joined, answered and left by a page on another machine", () => {
      cy.request<{ csrf: string; node: { user: string; host: string } }>(`${PEER}/api/session`).then(({ body }) => {
        expect(`${body.node.user}@${body.node.host}`).to.eq(PEER_LABEL);
        const csrf = body.csrf;
        cy.task("peerOpen", { url: PEER, page });

        cy.get(`button[aria-label="Chat with ${PEER_LABEL}"]`).click();
        cy.contains('[role="menuitem"]', "Start Chat").click();
        cy.get(MODAL).should("contain", `Chat with ${PEER_LABEL}`).find("#chat-name").clear().type("Dana{enter}");
        cy.get("#chat").should("be.visible").and("have.attr", "data-dock", "left");

        inviteFor(page).then((invite) => peerSays(csrf, "accept", { page, invite, name: "Sam" }));
        cy.get("#chat h2").should("have.text", "Dana, Sam");
        cy.get("#chat").should("contain", "Sam joined");

        cy.get("#chat-input").type("hello from studio-mini{meta}{enter}");
        peerHears(page, (e) => e.kind === "said" && e.text === "hello from studio-mini")
          .its("who")
          .should("include", { name: "Dana" });

        peerSays(csrf, "say", { page, id: "peer-msg-1", text: "seen it: https://example.org/peer" });
        cy.contains("#chat .chat-text", "seen it:").find("a").should("have.attr", "href", "https://example.org/peer");

        peerSays(csrf, "leave", { page });
        cy.get("#chat").should("contain", "Sam left");
        cy.get("#chat h2").should("have.text", "Dana");

        cy.get(`button[aria-label="Chat with ${PEER_LABEL}"]`).click();
        cy.contains('[role="menuitem"]', "Stop Chat").click();
        cy.get("#chat").should("not.exist");
      });
    });
  });

  // Step 5 of the integration scenario: the real server, no stub, refuses a verb without the CSRF token.
  it("refuses a chat verb that carries no CSRF token", () => {
    cy.request({ method: "POST", url: "/api/chat/leave", body: { page: "p-no-token" }, failOnStatusCode: false })
      .its("status")
      .should("eq", 403);
  });
});
