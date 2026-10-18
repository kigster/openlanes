import { MODAL } from "../support/selectors";

// Plan 017: the red pill opens the plan's files; spec.md is edited and saved against the real demo server and the
// plans tree bin/web-e2e copies to a temp dir (Cypress.env("plansDir")). Nothing is stubbed or intercepted.
describe("Plan files", () => {
  let ordinal = "";
  let folder = "";

  beforeEach(() => {
    cy.openBoard();
    // The plan to work on: blocked with a question and no car, which is what lets a save through.
    cy.request<{ me: { plans: Array<{ ordinal: string; cars: unknown[]; questions: unknown[] }> } }>("/api/board").then(({ body }) => {
      const plan = body.me.plans.find((p) => p.questions.length > 0 && p.cars.length === 0);
      expect(plan !== undefined, "a blocked demo plan with no car").to.equal(true);
      ordinal = plan!.ordinal;
    });
    cy.then(() => {
      const plansDir = Cypress.env("plansDir") as string;
      expect(plansDir, "CYPRESS plansDir env, set by bin/web-e2e").to.be.a("string");
      cy.task("log", `plans dir ${plansDir}`);
      cy.exec(`ls -d "${plansDir}"/${ordinal}* | head -1`).then(({ stdout }) => { folder = stdout.trim(); });
    });
  });

  const openDrawer = () => {
    cy.get(`.pill[data-plan="${ordinal}"]`).click();
    cy.get(".plan-drawer").should("be.visible");
  };
  const choose = (name: string) => cy.get('select[aria-label="Plan file"]').select(name);

  it("lists the files, shows blocked.md read only, replaces the popup, and saves spec.md", () => {
    openDrawer();
    cy.get('select[aria-label="Plan file"] option').then((options) => {
      const names = [...options].map((o) => (o as HTMLOptionElement).value).filter(Boolean);
      expect(names).to.include.members(["spec.md", "blocked.md"]);
    });

    choose("blocked.md");
    cy.get(MODAL).should("have.length", 1).and("contain", "blocked.md");
    cy.get(MODAL).contains("button", "Edit").should("not.exist");
    cy.get(MODAL).contains("button", "Close").click();

    choose("spec.md");
    cy.get(MODAL).should("have.length", 1).and("contain", "spec.md");
    cy.get(MODAL).contains("button", "Edit").click();
    cy.get(`${MODAL} .cm-content`).click().type("{ctrl+End}{enter}Saved by Cypress.");
    cy.get(MODAL).contains("button", "Save").click();
    cy.get(MODAL).contains("button", "Edit").should("exist");
    cy.get(MODAL).contains("button", "Close").click();

    choose("spec.md");
    cy.get(MODAL).should("contain", "Saved by Cypress.");

    cy.readFile(`${folder}/spec.md`).then((text: string) => {
      expect(text).to.contain("Saved by Cypress.");
      expect(text.startsWith("---\n")).to.equal(true);
    });
  });

  it("shows a conflict when the file was rewritten behind the popup", () => {
    openDrawer();
    choose("spec.md");
    cy.get(MODAL).contains("button", "Edit").click();
    cy.readFile(`${folder}/spec.md`).then((text: string) => {
      cy.writeFile(`${folder}/spec.md`, `${text}\nWritten behind the popup.\n`);
    });
    cy.get(`${MODAL} .cm-content`).click().type("{ctrl+End} mine");
    cy.get(MODAL).contains("button", "Save").click();
    cy.get(MODAL).contains("[role=alert]", "Conflict");
  });
});
