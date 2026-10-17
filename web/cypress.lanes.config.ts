// The lanes integration test (bin/lanes-e2e): Cypress drives the control room of a real `openlanes start -j 3` while real
// agents work three quick-lane plans, then checks /concurrency, /stop and /restart through the copilot. It spends
// tokens, so it is its own config and spec folder, which the everyday cypress.config.ts never picks up, and it refuses
// to start without OPENLANES_LANES_E2E=1.
import { defineConfig } from "cypress";

export default defineConfig({
  e2e: {
    specPattern: "cypress/lanes/**/*.cy.ts",
    supportFile: false,
    viewportWidth: 1440,
    viewportHeight: 900,
    defaultCommandTimeout: 15000,
    // A run is minutes of agent time; a retry would be another run, paid for twice.
    retries: 0,
    video: false,
    screenshotOnRunFailure: true,
    screenshotsFolder: "cypress/screenshots/lanes",
    setupNodeEvents(on, config) {
      if (process.env.OPENLANES_LANES_E2E !== "1") {
        throw new Error("The lanes test runs real agents and spends tokens. Run it with OPENLANES_LANES_E2E=1 just lanes-e2e.");
      }
      on("task", {
        log(message: string) {
          console.log(message);
          return null;
        },
      });
      return config;
    },
  },
});
