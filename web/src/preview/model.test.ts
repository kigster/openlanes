import fixture from "../api/fixtures/apps.json";
import type { AppStatus } from "../api/types";
import { appTabLabel, appTabValue, backend, overall, runningApps, withApp } from "./model";

const apps = fixture.apps as AppStatus[];
const [api, web] = apps;

describe("withApp", () => {
  it("adds a process it has not seen, and replaces one it has: the latest wins", () => {
    const once = withApp([api], web);
    const twice = withApp(once, { ...api, state: "restarting" });
    expect(twice.map(a => [a.process, a.state])).toEqual([
      ["api", "restarting"],
      ["web", "ready"],
    ]);
  });

  it("takes a stopped process off", () => {
    expect(withApp(apps, { ...web, state: "stopped" }).map(a => a.process)).toEqual(["api"]);
  });
});

describe("runningApps", () => {
  it("groups by plan, plans in order, one entry per plan with its preview process", () => {
    const other = { ...web, plan: "005.00", branch: "kig/005.00-x", port: 11102 };
    const got = runningApps([...apps, other]);
    expect(got.map(a => [a.plan, a.preview.process, a.processes.length])).toEqual([
      ["005.00", "web", 1],
      ["012.00", "web", 2],
    ]);
  });

  it("gives an app with no preview process no tab", () => {
    expect(runningApps([api])).toEqual([]);
  });

  it("is empty when nothing runs", () => {
    expect(runningApps([])).toEqual([]);
  });
});

describe("overall", () => {
  const app = (states: AppStatus["state"][]) => runningApps(apps.map((a, i) => ({ ...a, state: states[i] })))[0];

  it("is running when every process is ready", () => {
    expect(overall(app(["ready", "ready"]))).toBe("running");
  });

  it("is restarting while any process is starting or restarting", () => {
    expect([overall(app(["restarting", "ready"])), overall(app(["ready", "starting"]))]).toEqual(["restarting", "restarting"]);
  });

  it("is failed when any process failed", () => {
    expect(overall(app(["failed", "restarting"]))).toBe("failed");
  });
});

it("labels the tab with plan, branch and port, and names Restart backend's processes", () => {
  const [app] = runningApps(apps);
  expect([appTabLabel(app), appTabValue(app), backend(app).map(p => p.process)]).toEqual([
    "▶ 012 · kig/012.00-app-runner-and-preview · :11101",
    "app:012.00",
    ["api"],
  ]);
});
