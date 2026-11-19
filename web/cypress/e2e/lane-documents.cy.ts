import { DOCUMENT_ITEMS, DOCUMENT_MODAL, LANE_DOCUMENTS } from "../support/selectors";

// Plan 070: each wide lane's Documents dropdown opens a plan document in a read-only modal, against the real demo server
// and the plans tree bin/web-e2e copies to a temp dir (Cypress.env("plansDir")). Nothing is stubbed or intercepted.
describe("Lane documents", () => {
  let ordinal = "";
  let folder = "";
  const report = (violations: Array<{ id: string }>) => cy.task("log", `axe: ${violations.map((v) => v.id).join(", ")}`);

  beforeEach(() => {
    cy.viewport(1400, 900);
    cy.openBoard();
    cy.request<{ me: { plans: Array<{ ordinal: string; cars: unknown[]; questions: unknown[] }> } }>("/api/board").then(({ body }) => {
      const plan = body.me.plans.find((p) => p.questions.length > 0 && p.cars.length === 0);
      expect(plan !== undefined, "a blocked demo plan with no car").to.equal(true);
      ordinal = plan!.ordinal;
    });
    cy.then(() => {
      const plansDir = Cypress.env("plansDir") as string;
      expect(plansDir, "CYPRESS plansDir env, set by bin/web-e2e").to.be.a("string");
      cy.exec(`ls -d "${plansDir}"/${ordinal}* | head -1`).then(({ stdout }) => { folder = stdout.trim(); });
    });
  });

  const lane = () => cy.get(`[data-plan="${ordinal}"]`);
  const openMenu = () => lane().find(LANE_DOCUMENTS).should("be.enabled").click();

  it("lists Specification first and renders it with highlighted YAML frontmatter and a rendered body", () => {
    openMenu();
    cy.get(DOCUMENT_ITEMS).first().should("have.text", "Specification");
    cy.contains('[role="menuitem"]', "Specification").click();
    cy.get(DOCUMENT_MODAL).should("have.length", 1);
    cy.get(`${DOCUMENT_MODAL} .document-frontmatter code.language-yaml`).should("contain", "created:").find(".hljs-attr").should("exist");
    cy.get(`${DOCUMENT_MODAL} .md-preview h1`).should("exist");
    cy.injectAxe();
    cy.checkA11y(DOCUMENT_MODAL, { includedImpacts: ["serious", "critical"] }, report);
    cy.get(`${DOCUMENT_MODAL} .document-modal-x`).click();
    cy.get(DOCUMENT_MODAL).should("not.exist");
  });

  it("shows Pull requests last once the plan has one, and closes from the footer", () => {
    cy.then(() => cy.writeFile(`${folder}/pull-requests.md`, "# Pull Requests\n"));
    cy.reload();
    openMenu();
    cy.get(DOCUMENT_ITEMS).last().should("have.text", "Pull requests");
    cy.get(DOCUMENT_ITEMS).last().click();
    cy.get(DOCUMENT_MODAL).contains("button", "Close").click();
    cy.get(DOCUMENT_MODAL).should("not.exist");
  });

  it("lists a document written after the page loaded, without a reload", () => {
    openMenu();
    cy.contains('[role="menuitem"]', "Specification").should("exist");
    cy.contains('[role="menuitem"]', "Design").should("not.exist");
    cy.get("body").type("{esc}");
    cy.then(() => cy.writeFile(`${folder}/design.md`, "# Design\n\nWritten while the page was open.\n"));
    openMenu();
    cy.contains('[role="menuitem"]', "Design").click();
    cy.get(`${DOCUMENT_MODAL} .md-preview`).should("contain", "Written while the page was open.");
  });

  it("scrolls a long document from the keyboard and leaves nothing in <body> for a diagram that will not draw", () => {
    const body = `# Long\n\n\`\`\`mermaid\ngraph TD; A--\n\`\`\`\n\n${"A paragraph of text.\n\n".repeat(200)}`;
    cy.then(() => cy.writeFile(`${folder}/research.md`, body));
    openMenu();
    cy.contains('[role="menuitem"]', "Research").click();
    cy.get(`${DOCUMENT_MODAL} .mermaid-error`, { timeout: 15000 }).should("contain", "Could not draw this diagram");
    cy.get('body > [id^="dmermaid-"]').should("not.exist");
    cy.get(`${DOCUMENT_MODAL} .document-modal-body`).should("have.attr", "tabindex", "0").focus().should("have.focus");
    cy.injectAxe();
    cy.checkA11y(DOCUMENT_MODAL, { includedImpacts: ["serious", "critical"] }, report);
  });

  it("renders an admonition and a Mermaid diagram", () => {
    const body = "# Diagrams\n\n> [!NOTE]\n> Mind the gap.\n\n```mermaid\ngraph TD; A-->B\n```\n";
    cy.then(() => cy.writeFile(`${folder}/research.md`, body));
    cy.reload();
    openMenu();
    cy.contains('[role="menuitem"]', "Research").click();
    cy.get(`${DOCUMENT_MODAL} .admonition.is-note`).should("contain", "Mind the gap.");
    cy.get(`${DOCUMENT_MODAL} .mermaid-diagram svg`, { timeout: 15000 }).should("exist");
  });

  it("fills the viewport at 400px wide", () => {
    cy.viewport(400, 800);
    cy.reload();
    openMenu();
    cy.contains('[role="menuitem"]', "Specification").click();
    cy.get(DOCUMENT_MODAL).invoke("outerWidth").should("be.at.least", 398);
  });

  it("offers no Documents on narrow lanes", () => {
    cy.contains("button", "Narrow Lanes").click();
    cy.get(LANE_DOCUMENTS).should("not.exist");
  });
});
