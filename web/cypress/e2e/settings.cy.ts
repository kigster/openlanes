// Plan 058: the settings page against the real server, rooted in a temp project (see support/settingsRepo.ts) whose
// origin is a bare repo. Nothing is stubbed or intercepted.
describe("Project settings", () => {
  const plansDir = () => Cypress.env("plansDir") as string;
  const task = <T>(name: string) => cy.task(name, plansDir()) as unknown as Cypress.Chainable<T>;
  const save = () => cy.contains("button", "Save, commit and push to main").click();

  beforeEach(() => {
    task("settingsRepo:reset");
    cy.visit("/settings");
    cy.get("main.set-page").should("be.visible");
  });

  it("lists every key from the schema with each pane open, and folds one with −/+", () => {
    cy.request<{ keys: string[] }>("/api/settings").then(({ body }) => {
      cy.get('[name="jobs"]').should("exist");
      cy.get("section.set-pane").should("have.length.greaterThan", 3);
      for (const key of body.keys) cy.get(`.set-field label[for]`).filter(`:contains("${key}")`).should("exist");
    });
    cy.get('button[aria-label="Collapse commands"]').should("have.text", "−");
    cy.get('button[aria-label="Collapse General"]').click();
    cy.get('[name="jobs"]').should("not.exist");
    cy.get('button[aria-label="Open General"]').should("have.text", "+").click();
    cy.get('[name="jobs"]').should("exist");
  });

  it("shows a refused value on its field and leaves the file unchanged", () => {
    cy.get('[name="jobs"]').clear().type("0");
    save();
    cy.get('[name="jobs"]').closest(".set-field").find(".set-error").should("be.visible");
    task<string>("settingsRepo:file").should("equal", "jobs: 2\n");
    task<{ commits: number }>("settingsRepo:remote").its("commits").should("equal", 1);
  });

  it("makes no commit when nothing changed", () => {
    save();
    cy.get(".set-status").should("contain", "Nothing changed");
    task<{ commits: number }>("settingsRepo:remote").its("commits").should("equal", 1);
  });

  it("commits and pushes an edit to jobs, and the board reads it", () => {
    cy.get('[name="jobs"]').clear().type("5");
    save();
    cy.get(".set-status").should("contain", "Saved and pushed to main");
    task<{ file: string; commits: number }>("settingsRepo:remote").then(({ file, commits }) => {
      expect(file).to.match(/jobs:\s*5/);
      expect(commits).to.equal(2);
    });
    cy.request<{ values: { jobs: number } }>("/api/settings").its("body.values.jobs").should("equal", 5);
  });

  it("shows the refusal reason when .openlanes.yml has uncommitted edits", () => {
    task("settingsRepo:dirty");
    cy.get('[name="jobs"]').clear().type("7");
    save();
    cy.get(".set-refusal").should("be.visible").and("not.be.empty");
    task<{ commits: number }>("settingsRepo:remote").its("commits").should("equal", 1);
  });
});
