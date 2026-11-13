// Needs you: the rail of questions agents asked. Answering in words, answering yes or no, and holding one blocked.
describe("Needs you", () => {
  beforeEach(() => cy.openBoard());

  it("answers a question in words", () => {
    cy.get('.rail [data-ask="001.00/B1"]').within(() => {
      cy.get("textarea").type("Yes, carry the checkout id in every key.");
      cy.contains("button", "Send answer").click();
    });
    // The note folds into Answered, closed until asked for, so answered questions never crowd the open ones.
    cy.get(".rail details.answered").should("not.have.attr", "open");
    cy.get(".rail details.answered summary").should("contain", "Answered (1)").click();
    cy.get('.rail details.answered [data-ask="001.00/B1"]').should("be.visible").and("contain", "001.00").and("contain", "Answer sent to");
    cy.boardEventually((me) => me.plans.find((p) => p.ordinal === "001.00")?.questions.length === 0);
  });

  it("answers a yes or no question with one click", () => {
    cy.get('.rail [data-ask="006.00/B1"]').within(() => {
      cy.contains("button", "Yes").click();
    });
    cy.get('.rail [data-ask="006.00/B1"]').should("contain", "Answered yes to");
    cy.boardEventually((me) => me.plans.find((p) => p.ordinal === "006.00")?.questions.length === 0);
  });

  it("names a blocked lane's state beside its emoji, and its Unblock button spotlights its question", () => {
    cy.get('.plan[data-plan="001.00"] .plan-id').should("contain", "(Technical Block)");
    cy.get('.plan[data-plan="001.00"]').contains("button", "Unblock").click();
    cy.get('.rail .ask').first().should("have.attr", "data-ask", "001.00/B1").and("have.class", "is-spotlit");
    cy.focused().closest('[data-ask="001.00/B1"]').should("exist");
  });

  it("holds a question blocked, which takes it off the rail", () => {
    cy.get('.rail [data-ask="001.00/B1"]').within(() => {
      cy.contains("button", "Hold blocked").click();
    });
    cy.get('.rail [data-ask="001.00/B1"]').should("not.exist");
    cy.boardEventually((me) => me.plans.find((p) => p.ordinal === "001.00")?.questions[0]?.held === true);
  });
});
