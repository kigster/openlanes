// Cypress runs the built page against `openlanes web --demo` (contract.md): the API server over a pretend engine that
// publishes the fixture board and answers commands, so the specs drive the real page, server and Redis with no agents.
import { defineConfig } from "cypress";
import { closePeers, peerTasks } from "./cypress/peer";

export default defineConfig({
  e2e: {
    baseUrl: "http://127.0.0.1:11000",
    specPattern: "cypress/e2e/**/*.cy.ts",
    supportFile: "cypress/support/e2e.ts",
    viewportWidth: 1440,
    viewportHeight: 900,
    // The demo publishes once a second, so a reply can take that long to come back as `done`.
    defaultCommandTimeout: 8000,
    video: true,
    screenshotOnRunFailure: true,
    // The second machine (plan 006, I1): `just web-e2e` starts a second demo there, as demo@second-machine.
    env: { peer: "http://127.0.0.1:11101" },
    setupNodeEvents(on) {
      on("after:run", closePeers);
      // cypress-axe's violations go to the terminal as well as the command log, so CI shows them.
      on("task", {
        log(message: string) {
          console.log(message);
          return null;
        },
        ...peerTasks,
      });
    },
  },
});
