import type { Result } from "axe-core";
import { MODAL } from "../support/selectors";

// The whole flow with keys only: Tab and Shift+Tab to move, Enter and Space to press, Escape to leave, arrows in
// menus. Nothing here clicks or fires a pointer event, so a control a keyboard cannot reach fails the spec.
// cy.press supports Tab only (Cypress 14), and type() does not activate a focused button. The other keys go through
// the same DevTools channel cy.press uses, so the browser itself turns Enter and Space into a press.
const { TAB } = Cypress.Keyboard.Keys;
interface Key {
  key: string;
  code: string;
  keyCode: number;
  text?: string;
}
const ENTER: Key = { key: "Enter", code: "Enter", keyCode: 13, text: "\r" };
const SPACE: Key = { key: " ", code: "Space", keyCode: 32, text: " " };
const ESC: Key = { key: "Escape", code: "Escape", keyCode: 27 };
const HOME: Key = { key: "Home", code: "Home", keyCode: 36 };
const DOWN_ARROW: Key = { key: "ArrowDown", code: "ArrowDown", keyCode: 40 };

function key({ key: k, code, keyCode, text }: Key) {
  const base = { key: k, code, windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode };
  const send = (params: object) => Cypress.automation("remote:debugger:protocol", { command: "Input.dispatchKeyEvent", params });
  return cy
    .wrap(null, { log: false })
    .then(() => send({ ...base, type: text ? "keyDown" : "rawKeyDown", ...(text ? { text } : {}) }))
    .then(() => send({ ...base, type: "keyUp" }))
    .then(() => undefined);
}

const named = (tag: string, text: string) => (el: Element) => el.tagName === tag && (el.textContent ?? "").trim().startsWith(text);
const matching = (selector: string) => (el: Element) => el.matches(selector);

/** Tabs forward until the focused element satisfies `want`, failing if it never gets there. */
function tabTo(want: (el: Element) => boolean, left = 120): void {
  cy.document().then((doc) => {
    const el = doc.activeElement;
    if (el && el !== doc.body && want(el)) return;
    if (left <= 0) throw new Error(`Tab never reached the control; focus is on ${el?.outerHTML.slice(0, 160)}`);
    cy.press(TAB);
    tabTo(want, left - 1);
  });
}

const focusIs = (want: (el: Element) => boolean) =>
  cy.document().should((doc) => {
    expect(doc.activeElement && want(doc.activeElement), "the focused element").to.eq(true);
  });

function report(violations: Result[]) {
  cy.task("log", violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).join(" | ")}`).join("\n"));
}

const axe = () => {
  cy.injectAxe();
  cy.checkA11y(undefined, { includedImpacts: ["serious", "critical"] }, report);
};

describe("the keyboard flow", () => {
  beforeEach(() => {
    cy.openBoard();
    axe();
  });

  it("answers a question from Needs you", () => {
    const card = '.rail [data-ask="001.00/B1"]';
    tabTo(matching(`${card} textarea`));
    cy.focused().type("Yes, carry the checkout id in every key.", { delay: 0 });
    tabTo(named("BUTTON", "Send answer"));
    key(ENTER);
    cy.get(card).should("contain", "Answer sent to");
    cy.boardEventually((me) => me.plans.find((p) => p.ordinal === "001.00")?.questions.length === 0);
    axe();
  });

  it("holds a blocked question", () => {
    const card = '.rail [data-ask="001.00/B1"]';
    tabTo((el) => el.tagName === "BUTTON" && el.closest(card) !== null && (el.textContent ?? "").trim() === "Hold blocked");
    key(SPACE);
    cy.get(card).should("not.exist");
    cy.boardEventually((me) => me.plans.find((p) => p.ordinal === "001.00")?.questions[0]?.held === true);
    axe();
  });

  it("stops all local through its confirm dialog and returns focus to the button that opened it", () => {
    const opener = named("BUTTON", "Stop All Local");
    tabTo(opener);
    key(ENTER);
    cy.get(MODAL).should("be.visible");
    // The dialog opens on Cancel, so Enter there is the safe answer.
    focusIs(named("BUTTON", "Cancel"));
    axe();
    key(ESC);
    cy.get(MODAL).should("not.exist");
    focusIs(opener);
    cy.request("/api/board").its("body.me.run.status").should("eq", "running");

    key(ENTER);
    cy.get(MODAL).should("be.visible");
    cy.press(TAB); // Cancel -> Stop them
    focusIs(named("BUTTON", "Stop them"));
    key(ENTER);
    cy.get(MODAL).should("not.exist");
    focusIs(opener);
    cy.boardEventually((me) => me.run.status === "quitting");
  });

  it("opens the Action menu, closes it with Escape, and puts focus back on Action", () => {
    const action = named("BUTTON", "Action");
    tabTo(action);
    key(ENTER);
    cy.get('[role="menu"]').should("be.visible");
    key(DOWN_ARROW);
    // Radix hides the page behind a modal menu with aria-hidden, which axe reads as hidden focusable content; the
    // menu itself is what a person is in, so that is what is checked while it is open.
    cy.checkA11y('[role="menu"]', { includedImpacts: ["serious", "critical"] }, report);
    key(ESC);
    cy.get('[role="menu"]').should("not.exist");
    focusIs(action);
  });

  it("switches an agent's model from its drawer with the arrow keys", () => {
    const car = '[data-car="005.00/staff-reviewer"] .car-open';
    tabTo(matching(car));
    key(ENTER);
    cy.get(".drawer").should("contain", "staff-reviewer");
    tabTo(matching(".drawer .model-trigger"));
    key(ENTER);
    cy.get('[role="listbox"]').should("be.visible");
    // Arrow to Opus 5.5 and choose it; the listbox opens on the current model.
    const choose = (left = 12): void => {
      cy.document().then((doc) => {
        if ((doc.activeElement?.textContent ?? "").includes("Opus 5.5")) return;
        if (left <= 0) throw new Error(`the arrow keys never reached Opus 5.5; focus is on ${doc.activeElement?.textContent}`);
        key(DOWN_ARROW);
        choose(left - 1);
      });
    };
    key(HOME); // the list opens on the current model, so start from the top
    choose();
    key(ENTER);
    cy.boardEventually((me) => me.plans.flatMap((p) => p.cars).find((c) => c.key === "005.00/staff-reviewer")?.model === "claude-opus-5-5");
    cy.get(".drawer .drawer-meta").should("contain", "Model Opus 5.5");
    axe();
  });
});
