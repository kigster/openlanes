// Lane control, end to end, through the page only: three quick-lane plans running at once under a real `openlanes start
// -j 3`, then /concurrency, /stop and /restart typed into the copilot. Nothing is stubbed and no API is called to
// arrange or to check: the board is read through the cars and the header, the commands go in through the composer.
// Run by bin/lanes-e2e (just lanes-e2e), never by the everyday suite.
const HEADER = ".topbar-stat";
const TICK = 20000; // a stop is seen "within a tick"; this is a generous few of them
// STOP goes through the agent's control file, which it reads between steps, and the engine kills it 60 s later if it
// has not ended its turn, so a car can outlive /stop by up to a minute.
const STOP_GRACE = 90000;

interface Car { key: string; state: string }
interface Plan { ordinal: string; title: string; cars: Car[] }
interface Board { me: { plans: Plan[] } | null }

/** The ordinal of the plan whose title ends `suffix`, read from the board the page shows. */
const ordinalOf = (suffix: string) =>
  cy.request<Board>("/api/board").then(({ body }) => {
    const plan = body.me?.plans.find((p) => p.title.toLowerCase().endsWith(suffix));
    expect(plan, `plan "${suffix}" on the board`).not.to.equal(undefined);
    return plan!.ordinal;
  });

/** Sends one line through the copilot's composer and waits for the engine's answer to it. */
function say(text: string) {
  cy.get("#copilot-input").clear().type(text, { delay: 0 });
  cy.contains(".cp-composer button", "Send").click();
  return cy.contains(".cp-turn.is-you .cp-said", text).closest(".cp-turn").invoke("attr", "data-turn").then((id) =>
    cy.get(`[data-turn^="${id}."]`, { timeout: TICK }).should("exist").invoke("text"));
}

const cars = (ordinal: string) => cy.get(`[data-plan="${ordinal}"] [data-car]`, { timeout: TICK });

// One run, five steps in order: each test carries on the page the one before it left.
describe("lane control through the copilot", { testIsolation: false }, () => {
  let a = "";
  let b = "";

  before(() => {
    cy.visit("/", { onBeforeLoad: (win) => win.localStorage.setItem("openlanes-copilot-open", "1") });
    cy.get("#copilot-input", { timeout: 30000 }).should("be.visible");
  });

  it("1. runs the three plans at once; the header reads 3 of 3", () => {
    cy.get('[data-car]', { timeout: 120000 }).should("have.length.at.least", 3);
    cy.contains(HEADER, /3 of 3 agents/, { timeout: 60000 }).should("be.visible");
    ordinalOf("alpha").then((o) => { a = o; });
    ordinalOf("beta").then((o) => { b = o; });
  });

  it("2. /concurrency 2 is answered done, the header limit reads 2, and no car is killed", () => {
    say("/concurrency 2").should("match", /concurrency 3 → 2/);
    cy.contains(HEADER, /of 2 agents/).should("be.visible");
    cy.get('[data-car].is-failed, [data-car].is-stuck').should("not.exist");
  });

  it("3. /stop <plan A> is answered done and A's cars leave the board", () => {
    say(`/stop ${a}`).should("match", /stopped \d+ agents? on /);
    cy.get(`[data-plan="${a}"] [data-car]`, { timeout: STOP_GRACE }).should("not.exist");
  });

  it("4. /restart <plan A> brings a car back; /restart <plan B> while B runs is refused", () => {
    // Step 2 left two slots and B and C hold both, so a restarted A would wait in the queue for one of them to finish.
    say("/concurrency 3").should("match", /concurrency 2 → 3/);
    say(`/restart ${a}`).should("match", /restarts at the next tick/);
    cars(a).should("have.length.at.least", 1);
    say(`/restart ${b}`).should("match", /already has an agent/);
  });

  it("5. /frobnicate is answered with a help turn listing the three commands", () => {
    say("/frobnicate").then((help) => {
      for (const command of ["/stop", "/restart", "/concurrency"]) expect(help).to.contain(command);
    });
  });
});
