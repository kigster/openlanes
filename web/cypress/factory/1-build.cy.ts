// The factory, end to end, through the page: an idea typed into the control room of a real `openlanes start` becomes a
// quick-lane plan, real agents build it, and any question they ask is answered from Needs you. 2-product.cy.ts then
// plays the page they built. Run by bin/factory-e2e (just factory-e2e), never by the everyday suite.
import { MODAL } from "../support/selectors";

const IDEA =
  "A tic-tac-toe game in a single static index.html: two players take turns, it announces the winner or a draw, " +
  "and a Restart button clears the board.";

// Canned answers for whatever an agent asks, by what the question is about; anything else gets the fallback.
const ANSWERS: ReadonlyArray<readonly [RegExp, string]> = [
  [/\b(where|director|folder|path|file name)/i, "Put index.html in the repository root."],
  [/\b(framework|library|react|vue|typescript|build)/i, "No framework and no build step: plain HTML, CSS and JavaScript in the one file."],
  [/\btest/i, "No test runner. Opening the page and playing a game is the check."],
  [/\b(style|design|look|colou?r|theme)/i, "Plain and readable; any simple style is fine."],
];
const FALLBACK = "Use your recommendation.";

// As far as a factory with no GitHub remote can take a plan. 🟢 Ready for Review needs an open pull request, and a run
// that opens none (`--isolation shared`) leaves the finished build at 🟡 Building, done for this run, its builder's
// last line on the board's log saying so. 👀 and ✅ need a pull request and a person to merge it.
const BUILT = /^finished: completed\b.*built locally/;
const DEAD = ["discarded", "deferred"];

interface Question { id: string; heading: string; body: string; answers: string[] | null; held: boolean }
interface Plan { ordinal: string; title: string; lane: string; status: { key: string; emoji: string; label: string }; questions: Question[]; cars: Array<{ key: string; state: string; message: string }> }
interface LogLine { source: string; text: string; plan: string | null }
interface Board { me: { plans: Plan[]; run: { status: string }; log: LogLine[] } | null }

const isOurs = (plan: Plan) => /tic.?tac.?toe/i.test(plan.title);
const answerFor = (question: Question) => ANSWERS.find(([pattern]) => pattern.test(`${question.heading} ${question.body}`))?.[1] ?? FALLBACK;

/** Answers one question the way a person would: from its card in Needs you. */
function answer(question: Question) {
  cy.task("log", `answering ${question.id}: ${question.heading}`);
  cy.get(`.rail [data-ask="${question.id}"]`, { timeout: 30000 }).within(() => {
    if (question.answers?.length) {
      cy.contains("button", new RegExp(`^${question.answers[0]}$`, "i")).click();
    } else {
      cy.get("textarea").type(answerFor(question), { delay: 0 });
      cy.contains("button", "Send answer").click();
    }
  });
}

/** Whether the plan's build finished: 🟡, nobody on it, and its builder's closing log line. */
const built = (plan: Plan, log: LogLine[]) =>
  plan.status.key === "building" && plan.cars.every((c) => c.state !== "running") &&
  log.some((line) => line.plan === plan.ordinal && BUILT.test(line.text));

/** Polls the board until our plan's build has finished, answering questions on the way, until the deadline. */
function watch(deadline: number, answered: Set<string>, last = "") {
  cy.request<Board>({ url: "/api/board", log: false }).then(({ body }) => {
    const plan = body.me?.plans.find(isOurs);
    const seen = plan ? `${plan.status.emoji} ${plan.status.label} | ${plan.cars.map((c) => `${c.key} ${c.state}`).join(", ")}` : "not on the board yet";
    if (seen !== last) cy.task("log", `${new Date().toISOString()} ${plan?.ordinal ?? "plan"}: ${seen}`);
    if (plan && built(plan, body.me?.log ?? [])) return;
    if (plan && DEAD.includes(plan.status.key)) throw new Error(`the plan ended ${plan.status.label}, not built`);
    if (Date.now() > deadline) throw new Error(`the build did not finish in time; last seen: ${seen}`);
    plan?.questions.filter((q) => !q.held && !answered.has(q.id)).forEach((q) => {
      answered.add(q.id);
      answer(q);
    });
    cy.wait(10000, { log: false });
    watch(deadline, answered, seen);
  });
}

describe("the factory builds a tic-tac-toe page", () => {
  it("takes an idea from the page to a finished build, answering what the agents ask", () => {
    const deadline = Date.now() + Number(Cypress.env("minutes") ?? 15) * 60_000;

    cy.visit("/");
    cy.contains("button", "Action").click();
    cy.contains('[role="menuitem"]', "New idea").click();
    cy.get(MODAL).within(() => {
      // One builder (r2d2-mechanic), no research, no planner: the cheapest route that still builds the page.
      cy.contains("fieldset", "Lane").contains("label", "Quick").click();
      cy.contains("fieldset", "Front end").contains("label", "No").click();
      cy.contains("fieldset", "Depth").contains("label", "Fast").click();
      cy.get(".cm-content").click().type(IDEA, { delay: 0 });
      cy.contains("button", "Break it into plans").click();
    });
    cy.get(MODAL).should("not.exist");

    cy.contains(".plan-title", /tic.?tac.?toe/i, { timeout: 30000 }).should("be.visible")
      .closest("[data-plan]").find(".lane").should("contain", "Quick");

    watch(deadline, new Set());

    // The builder's own word is not a review: nothing on the board may say the plan was approved.
    cy.request<Board>("/api/board").its("body.me.log").then((log: LogLine[]) => {
      expect(log.map((l) => l.text).join("\n")).not.to.match(/approved, awaiting merge/);
    });
    cy.contains(".plan-title", /tic.?tac.?toe/i).closest("[data-plan]").should("exist");
  });
});
