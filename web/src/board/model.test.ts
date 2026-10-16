import { clock, dollars, fmt, lastSeen, planId, redactUrl, secondsBetween, shortAgent, span, stamp, who } from "./format";
import {
  LANES,
  carLook,
  hasRequest,
  isFinished,
  isWorking,
  lockMark,
  nodePlanKey,
  modelLabel,
  pillState,
  routeOf,
  rowColors,
  testRuns,
  testTabLabel,
  testTabValue,
} from "./model";
import { sampleBoard, sampleCar, samplePlan, samplePr, sampleQuestion } from "./sample";

const stations = sampleBoard().me.stations;

describe("format", () => {
  it("prints numbers and times as the mockup does", () => {
    expect([fmt(412), fmt(86000), fmt(1_240_000)]).toEqual(["412", "86.0k", "1.24M"]);
    expect([clock(42), clock(187), clock(-3)]).toEqual(["42s", "3m 07s", "0s"]);
    expect([span(187), span(2 * 3600 + 14 * 60)]).toEqual(["3m 07s", "2h 14m"]);
    expect(dollars(14.2)).toBe("$14.20");
    expect([planId("001.00"), planId("010.01")]).toEqual(["001", "010.01"]);
    expect(who({ user: "dana", host: "studio-mini" })).toBe("dana@studio-mini");
  });

  it("shortens an agent's name to what follows its first dash, and leaves a name with nothing to drop whole", () => {
    expect(["leah-researcher", "luke-backend", "r2d2-mechanic", "general-purpose", "Explore", "odd-", "a-b-c"].map(shortAgent))
      .toEqual(["researcher", "backend", "mechanic", "purpose", "Explore", "odd-", "b-c"]);
  });

  it("redacts a URL's userinfo, user name included", () => {
    expect(["redis://:pw@h:6379/0", "rediss://user:pw@h/1", "redis://user@h/2", "redis://h:6379/0"].map(redactUrl))
      .toEqual(["redis://:***@h:6379/0", "rediss://:***@h/1", "redis://:***@h/2", "redis://h:6379/0"]);
  });

  it("measures seconds between two times, never negative", () => {
    expect(secondsBetween("2026-10-13T09:00:00Z", "2026-10-13T09:01:05Z")).toBe(65);
    expect(secondsBetween("2026-10-13T09:01:00Z", "2026-10-13T09:00:00Z")).toBe(0);
    expect(secondsBetween(null, "2026-10-13T09:00:00Z")).toBe(0);
    expect(secondsBetween("nonsense", "2026-10-13T09:00:00Z")).toBe(0);
  });

  it("stamps log times and leaves unreadable ones alone", () => {
    expect(stamp("2026-10-13T09:00:05Z")).toMatch(/^\d\d:\d\d:05$/);
    expect(stamp("soon")).toBe("soon");
  });

  it("measures a machine's last heartbeat against our clock", () => {
    const b = sampleBoard();
    b.others[0].node.heartbeat_at = "2026-10-13T08:59:56Z";
    expect(lastSeen(b.others[0], b.me)).toBe(4);
  });
});

describe("routeOf", () => {
  it("fills the full lane up to its station", () => {
    const r = routeOf({ lane: "full", station: "building" }, stations);
    expect(r.stops).toEqual(["done", "done", "done", "here", "ahead", "ahead", "ahead"]);
    expect(r.segs).toEqual(["done", "done", "done", "ahead", "ahead", "ahead"]);
    expect(r.late).toBe(false);
  });

  it("draws the stations a lane does not use as off, and its skips as hollow rings", () => {
    const r = routeOf({ lane: "quick", station: "in_review" }, stations);
    expect(r.stops).toEqual(["off", "off", "off", "done", "skip", "here", "ahead"]);
    expect(r.segs.slice(0, 3)).toEqual(["off", "off", "off"]);
    expect(r.late).toBe(true);
  });

  it("treats an unknown station as the first", () => {
    expect(routeOf({ lane: "plan", station: "nowhere" }, stations).at).toBe(0);
  });
});

describe("rowColors", () => {
  it("is the lane while working, green once approved, purple once merged", () => {
    expect(rowColors(samplePlan({ lane: "quick" })).color).toBe(LANES.quick.color);
    expect(rowColors(samplePlan({ pr: samplePr({ state: "approved" }) })).color).toBe("var(--go)");
    expect(rowColors(samplePlan({ pr: samplePr({ state: "merged" }) })).color).toBe("var(--merged)");
  });
});

describe("carLook", () => {
  it("is red with the question when its agent asked one", () => {
    const plan = samplePlan({ questions: [sampleQuestion()] });
    expect(carLook(plan, plan.cars[0])).toEqual({ blocked: true, label: "needs you", activity: "Should Redis keys carry the checkout path?" });
  });

  it("falls back to the heading when the question has no body", () => {
    const plan = samplePlan({ questions: [sampleQuestion({ body: "" })] });
    expect(carLook(plan, plan.cars[0]).activity).toBe("B1 Redis key layout");
  });

  it("is red when stuck or failed, and plain otherwise", () => {
    const plan = samplePlan();
    expect(carLook(plan, sampleCar({ state: "stuck", message: "waiting" })).label).toBe("needs you");
    expect(carLook(plan, sampleCar({ state: "failed" })).label).toBe("failed");
    expect(carLook(plan, sampleCar()).blocked).toBe(false);
  });
});

describe("pillState", () => {
  const st = (over: Parameters<typeof samplePlan>[0], gone = false) => pillState(samplePlan(over), stations, gone);

  it("covers every state of the mockup's pill", () => {
    expect(st({}, true)).toMatchObject({ cls: "is-gone", mark: "✅" });
    expect(st({ pr: null }, true).say).toContain("PR #?");
    expect(st({ pr: samplePr({ state: "merged" }) })).toMatchObject({ cls: "is-merged", mark: "✅" });
    expect(st({ pr: samplePr({ state: "approved" }) })).toMatchObject({ cls: "is-done", mark: "✓", say: "reviewed, PR #44 ready to merge" });
    expect(st({ interrupted: { agent: "leah-researcher", at: "t", note: "" } })).toMatchObject({ cls: "is-blocked", mark: "⭕" });
    expect(st({ questions: [sampleQuestion({ held: true })] })).toMatchObject({ cls: "is-blocked is-held", mark: "⏸" });
    expect(st({ questions: [sampleQuestion({ owner: "product" })] })).toMatchObject({ mark: "🛑", say: expect.stringContaining("product") });
    expect(st({ questions: [sampleQuestion({ body: "" })] })).toMatchObject({ mark: "⭕", say: "needs technical decision: B1 Redis key layout" });
    expect(st({ questions: [sampleQuestion({ held: true, body: "" })] }).say).toContain("B1 Redis");
    expect(st({ questions: [sampleQuestion({ owner: "product", body: "" })] }).say).toContain("B1 Redis");
    expect(st({ cars: [sampleCar({ state: "stuck", message: "no reply" })] })).toMatchObject({ mark: "⭕", blocked: true });
    expect(st({})).toMatchObject({ cls: "", mark: "🛠️", say: "working, at Building" });
    expect(st({ station: "elsewhere" }).say).toBe("working, at elsewhere");
  });
});

describe("predicates and labels", () => {
  it("counts running and stuck cars as working, not done or failed ones", () => {
    expect(["running", "stuck", "done", "failed"].map(state => isWorking(sampleCar({ state: state as "running" })))).toEqual([true, true, false, false]);
    expect(nodePlanKey("abc", "010.00")).toBe("abc:010.00");
  });

  it("knows requests, finished plans and model labels", () => {
    expect(hasRequest(samplePlan({ questions: [sampleQuestion()] }))).toBe(true);
    expect(hasRequest(samplePlan())).toBe(false);
    expect(isFinished(samplePlan({ pr: samplePr({ state: "approved" }) }))).toBe(true);
    expect(isFinished(samplePlan())).toBe(false);
    const models = sampleBoard().me.models;
    expect(modelLabel(models, "claude-opus-5-5")).toBe("Opus 5.5");
    expect(modelLabel(models, "mystery")).toBe("mystery");
  });

  it("reads test runs from activity lines and labels their tabs", () => {
    const plan = samplePlan({
      cars: [
        sampleCar({ agent: "luke-backend", key: "001.00/luke-backend", message: "Running bundle exec rspec: 3 of 9" }),
        sampleCar({ agent: "rey-frontend", key: "001.00/rey-frontend", message: "Running npm test: 1 of 2" }),
        sampleCar({ agent: "yoda-writer", key: "001.00/yoda-writer", message: "Writing" }),
      ],
    });
    const runs = testRuns([plan]);
    expect(runs.map(r => [r.cmd, r.done, r.total])).toEqual([["bundle exec rspec", 3, 9], ["npm test", 1, 2]]);
    expect(testTabValue(runs[0])).toBe("tests:001.00/luke-backend");
    expect(testTabLabel(runs[0], runs)).toBe("001 tests, luke");
    expect(testTabLabel(runs[0], [runs[0]])).toBe("001 tests");
  });
});

describe("lockMark", () => {
  it("shows 🔑 with who holds the lock, and nothing for an unlocked plan", () => {
    const locked = { pid: 4242, host: "studio-mini", started_at: "2026-10-13T09:00:00Z" };
    expect(lockMark(samplePlan({ locked }))).toEqual({ mark: "🔑", title: expect.stringContaining("4242") });
    expect(lockMark(samplePlan({ locked }))?.title).toContain("studio-mini");
    expect(lockMark(samplePlan({ locked: null }))).toBeNull();
  });
});
