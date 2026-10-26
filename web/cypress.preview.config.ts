// The Preview tab's integration check (plan 012, F2): Cypress drives the built page served by a real
// `openlanes web --demo` on 127.0.0.1:11050, while its tasks start and stop a real `openlanes project start --demo` on the
// fixture app in spec/fixtures/apps/preview_project. Nothing is intercepted. Its own config and spec folder, so the
// everyday cypress.config.ts (the demo suite on 11000) never picks it up. Run it as `just preview-e2e`.
import { defineConfig } from "cypress";
import { spawn, type ChildProcess } from "node:child_process";
import { utimesSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const PROJECT = resolve(REPO, "spec/fixtures/apps/preview_project");
const PORT = Number(process.env.PREVIEW_E2E_PORT ?? 11050);

let app: ChildProcess | null = null;

/** TERM, as `openlanes project stop` sends, and wait for the runner to have stopped every process. */
function stopApp(): Promise<null> {
  const running = app;
  app = null;
  if (!running || running.exitCode !== null) return Promise.resolve(null);
  return new Promise(done => {
    running.once("exit", () => done(null));
    running.kill("SIGTERM");
  });
}

export default defineConfig({
  e2e: {
    baseUrl: `http://127.0.0.1:${PORT}`,
    specPattern: "cypress/preview/**/*.cy.ts",
    supportFile: false,
    viewportWidth: 1440,
    viewportHeight: 900,
    defaultCommandTimeout: 15000,
    // The app listens on its own port, another origin: reading the framed page needs this.
    chromeWebSecurity: false,
    video: false,
    screenshotOnRunFailure: true,
    setupNodeEvents(on) {
      on("task", {
        /** Starts the fixture app; `deny` makes its web process send X-Frame-Options: DENY. */
        async startApp({ deny }: { deny: boolean }) {
          await stopApp();
          app = spawn(resolve(REPO, "exe/openlanes"), ["project", "start", "--demo", "--control-room", `http://127.0.0.1:${PORT}`,
            "--redis-url", process.env.E2E_REDIS_URL ?? "redis://localhost:6379/13"], {
            cwd: PROJECT,
            env: { ...process.env, FIXTURE_FRAMING: deny ? "--deny" : "", NO_COLOR: "1" },
            stdio: ["ignore", "inherit", "inherit"],
          });
          return null;
        },
        stopApp,
        /** Moves a fixture file's mtime, as an edit would, without changing what git sees. */
        touch(path: string) {
          const now = new Date();
          utimesSync(resolve(PROJECT, path), now, now);
          return null;
        },
      });
      // The spec's own `after` stops it; this covers a run that ends early.
      process.once("exit", () => app?.kill("SIGTERM"));
    },
  },
});
