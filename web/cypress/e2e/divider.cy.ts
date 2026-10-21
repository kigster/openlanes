// The draggable divider between the board and the right-hand column (plan 018): a real browser against the built
// bundle and the demo server's real /api, nothing stubbed.
const SEP = '[role="separator"][aria-orientation="vertical"]';
const drawerWidth = () => cy.get(".drawer, .rail").then(($el) => $el[0].getBoundingClientRect().width);
const layoutWidth = () => cy.get("main.layout").then(($el) => $el[0].clientWidth);

function drag(from: number, to: number) {
  cy.get(SEP).trigger("pointerdown", { clientX: from, clientY: 200, button: 0, pointerId: 1, force: true });
  cy.get(SEP).trigger("pointermove", { clientX: to, clientY: 200, pointerId: 1, force: true });
  cy.get(SEP).trigger("pointerup", { clientX: to, clientY: 200, pointerId: 1, force: true });
}

describe("Column divider", () => {
  beforeEach(() => {
    cy.viewport(1400, 900);
    cy.clearLocalStorage();
    cy.openBoard();
  });

  it("sits between the board and the right-hand column", () => {
    cy.get(SEP).should("have.length", 1).and("have.attr", "aria-valuenow", "360");
  });

  it("follows a drag by the dragged distance, without a jump at pointerdown", () => {
    cy.get(SEP).then(($sep) => {
      const grab = Math.round($sep[0].getBoundingClientRect().left) + 10;
      drag(grab, grab - 100);
    });
    cy.get(SEP).should("have.attr", "aria-valuenow", "460");
    cy.get(".drawer, .rail").invoke("outerWidth").should("be.closeTo", 460, 1);
  });

  it("clamps at 360px and at 60% of the layout", () => {
    drag(1000, 100);
    layoutWidth().then((w) => cy.get(SEP).should("have.attr", "aria-valuenow", String(Math.floor(w * 0.6))));
    drag(300, 1300);
    cy.get(SEP).should("have.attr", "aria-valuenow", "360");
  });

  it("keeps the width across a reload and a drawer opening and closing", () => {
    cy.get(SEP).focus().type("{leftarrow}{leftarrow}");
    cy.get(SEP).should("have.attr", "aria-valuenow", "408");
    cy.reload();
    cy.get(SEP).should("have.attr", "aria-valuenow", "408");
    cy.get('[data-car="005.00/hansolo-reviewer"] .car-open').click();
    cy.get(".drawer").should("contain", "hansolo-reviewer");
    cy.get(SEP).should("have.attr", "aria-valuenow", "408");
    cy.get(".drawer").contains("button", "Close").click();
    cy.get(".rail").should("exist");
    cy.get(SEP).should("have.attr", "aria-valuenow", "408");
    drawerWidth().should("be.closeTo", 408, 1);
  });

  it("steps by 24 with the arrow keys and resets with Home and a double-click", () => {
    cy.get(SEP).focus().type("{leftarrow}");
    cy.get(SEP).should("have.attr", "aria-valuenow", "384");
    cy.get(SEP).type("{rightarrow}");
    cy.get(SEP).should("have.attr", "aria-valuenow", "360");
    cy.get(SEP).type("{leftarrow}{leftarrow}{home}");
    cy.get(SEP).should("have.attr", "aria-valuenow", "360");
    cy.get(SEP).type("{leftarrow}").dblclick({ force: true });
    cy.get(SEP).should("have.attr", "aria-valuenow", "360");
  });

  it("stays visible after the column scrolls", () => {
    cy.get(".drawer, .rail").scrollTo("bottom", { ensureScrollable: false });
    cy.get(SEP).should("be.visible");
  });

  it("is absent in a 900px-wide window", () => {
    cy.viewport(900, 900);
    cy.get(SEP).should("not.exist");
  });
});
