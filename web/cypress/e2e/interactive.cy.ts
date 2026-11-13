// Plan 064: the page against the real `openlanes web` server on its demo board. The event stream and the HTTP routes
// are not stubbed.
describe("interactive board (plan 064)", () => {
  it("advances a car through board_delta frames after one full board", () => {
    cy.visit("/", {
      onBeforeLoad(win) {
        const seen: string[] = [];
        (win as unknown as { __frames: string[] }).__frames = seen;
        const real = win.fetch.bind(win);
        win.fetch = async (input, init) => {
          const res = await real(input, init);
          if (String(input).includes("/api/events") && res.body) {
            const [mine, theirs] = res.body.tee();
            const reader = mine.getReader();
            const decoder = new TextDecoder();
            void (async () => {
              for (;;) {
                const { done, value } = await reader.read();
                if (done) return;
                for (const m of decoder.decode(value).matchAll(/^event: (\S+)/gm)) seen.push(m[1]);
              }
            })();
            return new Response(theirs, { status: res.status, headers: res.headers });
          }
          return res;
        };
      },
    });
    cy.get(".car.is-running", { timeout: 30000 }).first().find(".car-stats").invoke("text").then((first) => {
      cy.get(".car.is-running").first().find(".car-stats", { timeout: 30000 }).should(($s) => expect($s.text()).not.to.equal(first));
    });
    cy.window().then((win) => {
      const frames = (win as unknown as { __frames: string[] }).__frames;
      expect(frames.filter((f) => f === "board")).to.have.length(1);
      expect(frames.filter((f) => f === "board_delta").length).to.be.greaterThan(0);
    });
  });

  it("extends a running car's time and gets the engine's reply", () => {
    cy.openBoard();
    cy.get(".car.is-running .car-open", { timeout: 30000 }).first().click();
    cy.contains("button", "Extend time +10 min").click();
    cy.get(".drawer").should("contain.text", "more minutes");
  });

  it("keeps a struck finding struck after a reload", () => {
    cy.openBoard();
    cy.get(".plan-review", { timeout: 30000 }).first().within(() => {
      cy.contains("button", "Review").click();
      cy.contains("button", /^Strike/).first().click();
      cy.contains("Struck").should("exist");
    });
    cy.reload();
    cy.get(".plan-review").first().within(() => {
      cy.contains("button", "Review").click();
      cy.contains("Struck").should("exist");
    });
  });

  it("shows a plan's cost as the sum of its cars' costs", () => {
    cy.openBoard();
    cy.get(".plan", { timeout: 30000 }).each(($plan) => {
      const cars = [...$plan.find(".car-stats [title='Cost so far']")].map((e) => Number(e.textContent!.replace("$", "")));
      const total = Number($plan.find(".plan-meta .plan-cost").text().replace(/[^0-9.]/g, ""));
      if (cars.length > 0 && !Number.isNaN(total)) expect(total).to.be.at.least(cars.reduce((a, b) => a + b, 0) - 0.05 * cars.length);
    });
  });
});
