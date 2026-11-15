// The page at phone size (shell.css, max-width 600px): the bar pinned to the top with the toggles in a strip under
// it, the bar hidden behind a Nav button, and Needs you ahead of the board. A real browser, because none of this is
// in the markup: it is the stylesheet placing the same elements a wide page has.
const box = (selector: string) => cy.get(selector).then(($el) => $el[0].getBoundingClientRect());
// The page's own width: the viewport less a scrollbar, where the browser draws one.
const pageWidth = () => cy.document().then((doc) => doc.documentElement.clientWidth);

describe("on a phone", () => {
  beforeEach(() => {
    cy.viewport(390, 844);
    cy.clearLocalStorage();
    cy.openBoard();
  });

  it("pins the bar and its strip to the top, on one line, with nothing wider than the screen", () => {
    cy.scrollTo(0, 600);
    box(".topbar-row").then((row) => {
      expect(Math.round(row.top)).to.eq(0);
      expect(row.height).to.be.at.most(36); // half of the wide bar's 69px
      box(".logo").then((logo) => expect([Math.round(logo.left), Math.round(logo.top), Math.round(logo.height)]).to.deep.eq([0, 0, Math.round(row.height)]));
      box(".nav-toggles").then((strip) => {
        pageWidth().then((width) => expect([Math.round(strip.top), Math.round(strip.left), Math.round(strip.width)]).to.deep.eq([Math.round(row.bottom), 0, width]));
        expect(strip.height).to.be.within(20, 24);
      });
      // One line: every item of the row starts inside the row's own height.
      cy.get(".topbar-row > *:visible").each(($item) => expect($item[0].getBoundingClientRect().bottom).to.be.at.most(row.bottom + 1));
    });
    cy.document().then((doc) => expect(doc.documentElement.scrollWidth).to.eq(doc.documentElement.clientWidth));
  });

  it("keeps the three toggles in the strip, joined and centred, and Actions and Stop behind Menu", () => {
    const names = ["All Machines", "Narrow Lanes", "Hide Inactive"];
    names.forEach((name) => cy.contains(".nav-toggles button", name).should("be.visible").find(".nav-check").should("be.visible"));
    cy.get(".nav-toggles button").then(($buttons) => {
      const boxes = [...$buttons].map((b) => b.getBoundingClientRect());
      expect(boxes.map((b, i) => (i === 0 ? 0 : Math.round(b.left - boxes[i - 1].right))), "no gaps").to.deep.eq([0, 0, 0]);
      expect(Math.abs(boxes[0].left - ($buttons[0].ownerDocument.documentElement.clientWidth - boxes[2].right)), "centred").to.be.at.most(1);
      expect([...$buttons].map((b) => getComputedStyle(b).borderRadius)).to.deep.eq(["0px", "0px", "0px"]);
    });
    cy.contains("button", "Stop Local Workers").should("not.be.visible");
    cy.contains(".nav-toggles button", "Narrow Lanes").click().should("have.attr", "aria-pressed", "true");
    cy.get("main.layout").should("have.attr", "data-lanes", "narrow");
    cy.get(".nav-burger").click().should("have.attr", "aria-expanded", "true");
    cy.contains("button", "Stop Local Workers").should("be.visible");
    cy.contains("button", "Action").should("be.visible");
    cy.get("body").type("{esc}");
    cy.contains("button", "Stop Local Workers").should("not.be.visible");
  });

  it("hides the bar behind Nav, remembers it across a reload, and brings it back", () => {
    cy.get('button[aria-label="Hide navigation"]').click();
    cy.get(".topbar-row").should("not.be.visible");
    cy.get(".nav-toggles").should("not.be.visible");
    cy.scrollTo(0, 600);
    cy.contains("button", "Nav").should("be.visible").and("have.attr", "aria-expanded", "false").and("have.focus");
    box(".nav-restore").then((nav) => expect(Math.round(nav.top)).to.eq(0));
    cy.reload();
    cy.contains("button", "Nav").should("be.visible").click();
    cy.get(".topbar-row").should("be.visible");
    cy.get('button[aria-label="Hide navigation"]').should("have.focus").and("have.attr", "aria-expanded", "true");
  });

  it("puts Needs you straight under the status line and ahead of the board, each as wide as the other", () => {
    box(".statusline").then((line) => {
      box(".rail").then((rail) => {
        box(".board").then((board) => {
          expect(rail.top).to.be.within(line.bottom, line.bottom + 16);
          expect(Cypress.$(".tab")[0].getBoundingClientRect().top).to.be.greaterThan(rail.bottom);
          expect(board.top).to.be.greaterThan(rail.bottom);
          const edges = [line, rail, board].map((b) => [Math.round(b.left), Math.round(b.width)]);
          pageWidth().then((width) => expect(edges).to.deep.eq([[16, width - 32], [16, width - 32], [16, width - 32]]));
        });
      });
    });
  });
});
