// The settings spec's project (plan 058): the plans dir bin/web-e2e hands out lives in a temp project root, which these
// tasks turn into a git repo on `main` whose `origin` is a bare repo, so a save has somewhere real to push.
import { execFileSync } from "node:child_process";
import { mkdtempSync, appendFileSync, existsSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const git = (cwd: string, ...args: string[]): string => execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
const rootOf = (plansDir: string) => dirname(plansDir);
const bareOf = (plansDir: string) => join(rootOf(plansDir), ".origin-path");

export const settingsRepoTasks = {
  /** Idempotent: makes the repo and its bare origin once, then puts both back at the first commit. */
  "settingsRepo:reset": (plansDir: string): string => {
    const root = rootOf(plansDir);
    if (!existsSync(join(root, ".git"))) {
      const bare = mkdtempSync(join(tmpdir(), "ol-settings-origin-"));
      git(bare, "init", "--bare", "-b", "main");
      git(root, "init", "-b", "main");
      git(root, "config", "user.email", "e2e@example.test");
      git(root, "config", "user.name", "E2E");
      git(root, "config", "commit.gpgsign", "false");
      git(root, "remote", "add", "origin", bare);
      writeFileSync(bareOf(plansDir), bare);
      writeFileSync(join(root, ".openlanes.yml"), "jobs: 2\n");
      writeFileSync(join(root, ".gitignore"), ".plans/\n.origin-path\n");
      git(root, "add", ".openlanes.yml", ".gitignore");
      git(root, "commit", "-m", "Seed settings");
      git(root, "push", "-u", "origin", "main");
    }
    const first = git(root, "rev-list", "--max-parents=0", "HEAD");
    git(root, "reset", "--hard", first);
    git(root, "push", "--force", "origin", "main");
    return first;
  },
  /** Leaves an uncommitted edit in .openlanes.yml, which is what the dirty_config guard looks for. */
  "settingsRepo:dirty": (plansDir: string): null => {
    appendFileSync(join(rootOf(plansDir), ".openlanes.yml"), "# edited by hand\n");
    return null;
  },
  /** What the bare remote's main holds for .openlanes.yml, and how many commits it has. */
  "settingsRepo:remote": (plansDir: string): { file: string; commits: number } => {
    const bare = execFileSync("cat", [bareOf(plansDir)], { encoding: "utf8" }).trim();
    return { file: git(bare, "show", "main:.openlanes.yml"), commits: Number(git(bare, "rev-list", "--count", "main")) };
  },
  "settingsRepo:file": (plansDir: string): string => execFileSync("cat", [join(rootOf(plansDir), ".openlanes.yml")], { encoding: "utf8" }),
};
