// /restart-web end to end, through the page only, against a real `openlanes start` (bin/lanes-e2e): the supervisor
// stops the web server, rebuilds web/dist and starts it again on the same port. It lives beside lanes.cy.ts, not in
// cypress/e2e, because only a supervised run has a supervisor to signal; the demo behind `just web-e2e` has none.
// Nothing is stubbed. Run by bin/lanes-e2e, never by the everyday suite.
export {};
const TICK = 20000;
// stop, `npm run build` (WebRebuild::TIMEOUT is 300 s), start: the page must outwait all three.
const RESTART = 330000;

/** Sends one line through the copilot's composer and yields the id of the turn it created. */
function send(text: string) {
  cy.get("#copilot-input").clear().type(text, { delay: 0 });
  cy.contains(".cp-composer button", "Send").click();
  return cy.contains(".cp-turn.is-you .cp-said", text).closest(".cp-turn").invoke("attr", "data-turn");
}

describe("/restart-web through the copilot", { testIsolation: false }, () => {
  before(() => {
    cy.visit("/", { onBeforeLoad: (win) => win.localStorage.setItem("openlanes-copilot-open", "1") });
    cy.get("#copilot-input", { timeout: 30000 }).should("be.visible");
  });

  it("1. /stats is answered in the same session", () => {
    send("/stats").then((id) => cy.get(`[data-turn^="${id}."]`, { timeout: TICK }).should("exist"));
  });

  it("2. /restart-web is answered 'restarting the control room' before the server goes away", () => {
    send("/restart-web").then((id) => {
      cy.get(`[data-turn^="${id}."]`, { timeout: TICK }).invoke("text").should("match", /restarting the control room/i);
      cy.wrap(id).as("restartId");
    });
  });

  it("3. the page reconnects and the build outcome arrives as a copilot turn", function () {
    // The outcome is a copilot turn the new server writes on boot; it is not the answer to the message (`<id>.1`).
    cy.get(`.cp-turn:not(.is-you):not([data-turn^="${this.restartId}."])`, { timeout: RESTART })
      .last()
      .invoke("text")
      .should("match", /build|rebuil/i);
  });

  it("4. the board works afterwards", () => {
    cy.request({ url: "/healthz", timeout: TICK }).its("status").should("eq", 200);
    cy.get("[data-car], [data-plan]", { timeout: TICK }).should("exist");
    cy.get("#copilot-input").should("be.visible");
  });
});
