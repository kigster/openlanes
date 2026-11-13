// Plan 068: talk a blocked plan's question through with the unblocker. Against the real --demo server, whose
// responder asks two canned questions and then offers a decision; nothing is stubbed or intercepted.
describe("Unblock interview", () => {
  let ordinal = "";

  beforeEach(() => {
    cy.openBoard();
    cy.request<{ me: { plans: Array<{ ordinal: string; cars: unknown[]; questions: unknown[] }> } }>("/api/board").then(({ body }) => {
      const plan = body.me.plans.find((p) => p.questions.length > 0 && p.cars.length === 0);
      expect(plan !== undefined, "a blocked demo plan with no car").to.equal(true);
      ordinal = plan!.ordinal;
    });
  });

  const panel = () => cy.get(".interview");
  const open = () => {
    cy.get(`.ask[data-plan="${ordinal}"]`).contains("button", "Talk it through").click();
    panel().should("be.visible");
  };

  it("asks one question at a time, keeps the conversation over a reload, and confirms a decision", () => {
    open();
    // First question: answered with a button, the recommended one.
    panel().find(".is-recommended").should("have.length", 1).click();
    // Second question: answered in words.
    panel().find(".iv-turn").should("have.length.at.least", 3);
    panel().find("textarea").type("Skip it for now, and fix it next week.");
    panel().contains("button", "Send").click();
    panel().contains("button", "Confirm").should("be.visible");
    panel().find(".iv-turn").its("length").then((count) => {
      // A reload shows the same conversation.
      cy.reload();
      cy.get(".ask").should("exist");
      open();
      panel().contains("button", "Confirm").should("be.visible");
      panel().find(".iv-turn").should("have.length", count);
    });
    panel().contains("button", "Confirm").click();
    // The answer is accepted and the card is gone. The demo has no blocked.md to read the answer back from; the Ruby suite covers the file.
    cy.get(`.ask[data-plan="${ordinal}"]`).should("not.exist");
  });
});
