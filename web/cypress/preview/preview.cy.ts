// The three checks of plan 012's "How to tell it's working?", against a real app runner and a real control room.
const TAB = /▶ 012 · kig\/012\.00-app-runner-and-preview · :\d+/;

/** The framed page's element, read across origins (chromeWebSecurity is off in this config). */
const framed = (selector: string) =>
  cy.get("iframe.preview-frame").its("0.contentDocument.body").should("not.be.empty").then(cy.wrap).find(selector);

describe("the Preview tab", () => {
  after(() => cy.task("stopApp"));

  it("starts the API before the web page, shows the web page labelled with plan, branch and port, and restarts only the API", () => {
    cy.task("startApp", { deny: false });
    cy.visit("/");
    cy.contains('[role="tab"]', TAB, { timeout: 30000 }).click();
    cy.contains('[role="status"]', "● running");
    cy.contains('[role="tab"]', TAB).invoke("text").then(label => {
      const port = label.split(":").pop();
      cy.get("iframe.preview-frame").should("have.attr", "src", `http://127.0.0.1:${port}/`);
      framed("#port").should("have.text", port);
    });
    framed("#name").should("have.text", "web");
    // The web process looked for the API as it started, and found it answering.
    framed("#sibling").invoke("text").should("match", /^answered \d+$/);

    framed("#pid").invoke("text").then(pid => {
      cy.task("touch", "api/handler.rb");
      cy.contains('[role="status"]', "◐ restarting");
      cy.contains('[role="status"]', "● running");
      framed("#pid").should("have.text", pid);
    });
  });

  it("opens an app that refuses framing in a window of its own", () => {
    cy.task("startApp", { deny: true });
    cy.visit("/", {
      onBeforeLoad(win) {
        cy.stub(win, "open").as("open");
      },
    });
    cy.contains('[role="tab"]', TAB, { timeout: 30000 }).click();
    cy.contains("refuses to be shown in a frame");
    cy.get("iframe.preview-frame").should("not.exist");
    cy.contains("button", /^Open http:\/\/127\.0\.0\.1:\d+\/ in a new window$/).click();
    cy.get("@open").should("have.been.calledWithMatch", /^http:\/\/127\.0\.0\.1:\d+\/$/, "_blank", "noopener");
  });
});
