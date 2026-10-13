// The factory integration test (bin/factory-e2e): Cypress drives the control room of a real `openlanes start` while real
// agents build a tic-tac-toe page, then plays it. It spends tokens, so it is its own config and spec folder, which the
// everyday cypress.config.ts never picks up, and it refuses to start without OPENLANES_FACTORY_E2E=1.
import { defineConfig } from "cypress";
import { createReadStream, existsSync, readdirSync, realpathSync, statSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { dirname, extname, isAbsolute, join, relative, resolve } from "node:path";

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png",
};

// Never looked in: the plans, git's own files, and anything installed.
const SKIP = new Set([".git", ".plans", "node_modules"]);

/** The page the agents built: the shallowest index.html in the project, outside .plans. */
function findProduct(dir: string, depth = 0): string | null {
  if (depth > 3 || !existsSync(dir)) return null;
  const entries = readdirSync(dir).filter((name) => !SKIP.has(name)).sort();
  if (entries.includes("index.html")) return join(dir, "index.html");
  for (const name of entries) {
    const path = join(dir, name);
    if (!statSync(path).isDirectory()) continue;
    const found = findProduct(path, depth + 1);
    if (found) return found;
  }
  return null;
}

/**
 * The canonical path of `request` under `root`, or null when it is missing or lands outside: the page is written by an
 * agent, so `..`, a sibling sharing the root's prefix, and a symlink pointing out are all refused.
 */
function inside(root: string, request: string): string | null {
  const wanted = join(root, request);
  if (!existsSync(wanted)) return null;
  const real = realpathSync(wanted);
  const rel = relative(root, real);
  return rel.startsWith("..") || isAbsolute(rel) ? null : real;
}

let serving: { root: string; url: Promise<string>; server: Server } | null = null;

/**
 * Serves `dir` on 127.0.0.1, the way a person would open the page, and answers with its URL. The same URL every time
 * for the same directory: a visit to a new origin reloads the spec, which asks again, and a fresh port each time
 * would be a fresh origin, reloading forever.
 */
function serve(dir: string): Promise<string> {
  // Canonical, so the containment check below compares like with like: the temp dir arrives as `T//openlanes-…`,
  // and on macOS under the /var -> /private/var symlink.
  const root = realpathSync(resolve(dir));
  if (serving?.root === root) return serving.url;
  serving?.server.close();
  const server = createServer((req, res) => {
    const path = inside(root, decodeURIComponent(new URL(req.url ?? "/", "http://x").pathname).replace(/\/$/, "/index.html"));
    if (!path || statSync(path).isDirectory()) {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { "Content-Type": TYPES[extname(path)] ?? "application/octet-stream" });
    createReadStream(path).pipe(res);
  });
  const url = new Promise<string>((done) => {
    server.listen(0, "127.0.0.1", () => done(`http://127.0.0.1:${(server.address() as AddressInfo).port}/`));
  });
  serving = { root, url, server };
  return url;
}

export default defineConfig({
  e2e: {
    specPattern: "cypress/factory/**/*.cy.ts",
    supportFile: false,
    viewportWidth: 1440,
    viewportHeight: 900,
    defaultCommandTimeout: 15000,
    // One build is minutes of agent time; a retry would be another build, paid for twice.
    retries: 0,
    video: false,
    screenshotOnRunFailure: true,
    screenshotsFolder: "cypress/screenshots/factory",
    setupNodeEvents(on, config) {
      if (process.env.OPENLANES_FACTORY_E2E !== "1") {
        throw new Error("The factory test runs real agents and spends tokens. Run it with OPENLANES_FACTORY_E2E=1 just factory-e2e.");
      }
      if (!config.env.projectDir) throw new Error("projectDir is not set; bin/factory-e2e sets it to the throwaway repository.");
      on("task", {
        log(message: string) {
          console.log(message);
          return null;
        },
        findProduct(dir: string) {
          return findProduct(dir);
        },
        serveProduct(file: string) {
          return serve(dirname(file));
        },
      });
      return config;
    },
  },
});
