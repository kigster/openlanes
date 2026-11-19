// Plan 058: the settings page against the real server, rooted in a temp project (see support/settingsRepo.ts) whose
// origin is a bare repo. Nothing is stubbed or intercepted.
describe("Project settings", () => {
  const plansDir = () => Cypress.env("plansDir") as string;
  const task = <T>(name: string) => cy.task(name, plansDir()) as unknown as Cypress.Chainable<T>;
  const save = () => cy.contains("button", "Save, commit and push to main").click();
  // Panes load folded: open General, where jobs lives.
  const openGeneral = () => cy.get('button[aria-label="Open General"]').click();

  beforeEach(() => {
    task("settingsRepo:reset");
    cy.visit("/settings");
    cy.get("main.set-page").should("be.visible");
  });

  it("loads every pane folded, lists every key once opened, and folds one with −/+", () => {
    cy.get(".set-page h1").should("have.text", "Project Settings");
    cy.get('[name="jobs"]').should("not.exist");
    cy.get('button[aria-label="Open General"]').should("have.text", "+");
    // Open every pane, the sub-panes that appear as their parents open included.
    const openAll = (): void => {
      cy.get("body").then($b => {
        const next = $b.find('button.fold-toggle[aria-label^="Open "]').first();
        if (next.length) cy.wrap(next).click().then(openAll);
      });
    };
    openAll();
    cy.request<{ keys: string[] }>("/api/settings").then(({ body }) => {
      for (const key of body.keys) cy.get(`.set-field [name="${key}"], .set-field [name^="${key}."]`).should("exist");
    });
    cy.get('label[for]').contains(/^Jobs$/).should("exist");
    cy.get('button[aria-label="Collapse General"]').should("have.text", "−").click();
    cy.get('[name="jobs"]').should("not.exist");
  });

  it("jumps to a pane from the nav's settings menu, folding the one that was open", () => {
    openGeneral();
    cy.get('button[aria-label="Project settings sections"]').click();
    cy.get(".page-menu").contains("button", /^Merge$/).click();
    cy.get(".page-menu").should("not.exist");
    cy.get("#set-pane-merge").should("be.visible");
    cy.get('button[aria-label="Collapse Merge"]').should("exist");
    cy.get('button[aria-label="Open General"]').should("exist");
    cy.get(".page-menu, #set-pane-commands").should("not.exist");
  });

  it("shows a refused value on its field and leaves the file unchanged", () => {
    openGeneral();
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
    openGeneral();
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
    openGeneral();
    cy.get('[name="jobs"]').clear().type("7");
    save();
    cy.get(".set-refusal").should("be.visible").and("not.be.empty");
    task<{ commits: number }>("settingsRepo:remote").its("commits").should("equal", 1);
  });
});
