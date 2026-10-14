// What a plan looks like on the board, derived from the Snapshot alone. Pure functions, so the rules (which stop is
// skipped, when a row turns green, what a pill says) are tested without rendering anything.
import type { Car, Lane, ModelChoice, Plan, Question, Station } from "../api/types";
import { planId } from "./format";

export interface LaneLook {
  label: string;
  color: string;
  bg: string;
  /** The station the lane enters at; stations before it are drawn off. */
  from: string;
  /** Stations the lane passes without stopping: a hollow ring. */
  skip: string[];
}

/**
 * The lanes as lifecycle/lanes.rb moves them: full enters at New, plan at Planning, quick at Building and skips
 * Building UI. The Snapshot names a plan's lane but not where the lane enters, so this table is the one fact the page
 * keeps for itself (see the report on the contract).
 */
export const LANES: Record<Lane, LaneLook> = {
  full: { label: "Full lane", color: "var(--lane-full)", bg: "var(--lane-full-bg)", from: "new", skip: [] },
  plan: { label: "Plan lane", color: "var(--lane-plan)", bg: "var(--lane-plan-bg)", from: "ready_for_planning", skip: [] },
  quick: { label: "Quick lane", color: "var(--lane-quick)", bg: "var(--lane-quick-bg)", from: "building", skip: ["building_ui"] },
};

export type StopState = "off" | "skip" | "done" | "here" | "ahead";

export interface Route {
  /** The plan's column. */
  at: number;
  stops: StopState[];
  /** One per gap between stations: travelled, ahead (dotted), or off the lane. */
  segs: Array<"done" | "ahead" | "off">;
  /** Near the end of the line the cars hang leftwards so they never run off the board. */
  late: boolean;
}

export function stationIndex(stations: Station[], key: string): number {
  return Math.max(0, stations.findIndex(s => s.key === key));
}

export function routeOf(plan: Pick<Plan, "lane" | "station">, stations: Station[]): Route {
  const lane = LANES[plan.lane];
  const at = stationIndex(stations, plan.station);
  const from = stationIndex(stations, lane.from);
  const stops = stations.map((s, i): StopState =>
    i < from ? "off" : lane.skip.includes(s.key) ? "skip" : i < at ? "done" : i === at ? "here" : "ahead");
  const segs = stations.slice(0, -1).map((_, i) => (i < from ? "off" : i + 1 <= at ? "done" : "ahead"));
  return { at, stops, segs, late: at >= stations.length - 2 };
}

export const isMerged = (plan: Plan): boolean => plan.pr?.state === "merged";
export const isApproved = (plan: Plan): boolean => plan.pr?.state === "approved";

/**
 * A row wears its state: lane colours while it works, green once approved, purple once GitHub reports the merge.
 * Purple means merged on GitHub and nothing less.
 */
export function rowColors(plan: Plan): { color: string; bg: string } {
  if (isMerged(plan)) return { color: "var(--merged)", bg: "color-mix(in srgb, var(--merged) 16%, var(--plate))" };
  if (isApproved(plan)) return { color: "var(--go)", bg: "color-mix(in srgb, var(--go) 14%, var(--plate))" };
  const lane = LANES[plan.lane];
  return { color: lane.color, bg: lane.bg };
}

/** The question a car is blocked on: the plan's open question that agent asked. Held ones count; they still block. */
export const questionOf = (plan: Plan, car: Car): Question | undefined => plan.questions.find(q => q.agent === car.agent);

export interface CarLook {
  blocked: boolean;
  /** "needs you", "failed", or nothing: the label that replaces the model in the car's corner. */
  label: string;
  activity: string;
}

/** A car is red while its agent waits on a person (a question, or stuck) and when it failed. */
export function carLook(plan: Plan, car: Car): CarLook {
  const q = questionOf(plan, car);
  if (q) return { blocked: true, label: "needs you", activity: q.body || q.heading };
  if (car.state === "stuck") return { blocked: true, label: "needs you", activity: car.message };
  if (car.state === "failed") return { blocked: true, label: "failed", activity: car.message };
  return { blocked: false, label: "", activity: car.message };
}

export const modelLabel = (models: ModelChoice[], id: string): string => models.find(m => m.id === id)?.label ?? id;

export interface PillState {
  cls: string;
  mark: string;
  say: string;
  blocked: boolean;
}

/** The mockup's pillState: what a plan's pill looks like and says. `gone` is a merged plan whose row has left. */
export function pillState(plan: Plan, stations: Station[], gone = false): PillState {
  const pr = plan.pr;
  if (gone) return { cls: "is-gone", mark: "✅", say: `PR #${pr?.number ?? "?"} merged on GitHub, plan complete`, blocked: false };
  if (pr && isMerged(plan)) return { cls: "is-merged", mark: "✅", say: `PR #${pr.number} merged on GitHub, plan complete`, blocked: false };
  if (pr && isApproved(plan)) return { cls: "is-done", mark: "✓", say: `reviewed, PR #${pr.number} ready to merge`, blocked: false };
  if (plan.interrupted) {
    return { cls: "is-blocked", mark: "⭕", say: "needs a decision: keep or discard the interrupted agent's work", blocked: true };
  }
  const held = plan.questions.find(q => q.held);
  if (held) return { cls: "is-blocked is-held", mark: "⏸", say: `held blocked by you: ${held.body || held.heading}`, blocked: true };
  const open = plan.questions[0];
  if (open) {
    return open.owner === "product"
      ? { cls: "is-blocked", mark: "🛑", say: `needs product decision: ${open.body || open.heading}`, blocked: true }
      : { cls: "is-blocked", mark: "⭕", say: `needs technical decision: ${open.body || open.heading}`, blocked: true };
  }
  const stuck = plan.cars.find(c => c.state === "stuck" || c.state === "failed");
  if (stuck) return { cls: "is-blocked", mark: "⭕", say: `needs technical decision: ${stuck.message}`, blocked: true };
  const at = stations.find(s => s.key === plan.station)?.label ?? plan.station;
  return { cls: "", mark: "🛠️", say: `working, at ${at}`, blocked: false };
}

/** The mark a plan wears while a process holds its folder lock, and what hovering it says. Null when unlocked. */
export function lockMark(plan: Plan): { mark: string; title: string } | null {
  if (!plan.locked) return null;
  const { pid, host, started_at } = plan.locked;
  return { mark: "🔑", title: `locked by pid ${pid} on ${host}, since ${started_at}` };
}

/** A plan with something for a person to answer: a question or an interrupted agent. Its red pill opens the widget. */
export const hasRequest = (plan: Plan): boolean => plan.questions.length > 0 || plan.interrupted !== null;

/** Finished, as the status bar sorts: approved or merged. */
export const isFinished = (plan: Plan): boolean => isApproved(plan) || isMerged(plan);

export const rowDomId = (ordinal: string): string => `row-${ordinal}`;

export const describePlan = (plan: Plan): string => `${planId(plan.ordinal)} ${plan.title}`;

/** A car's test run, read from its activity line ("Running npm test: 52 of 465"); the contract has no test stream yet. */
export interface TestRun {
  plan: Plan;
  car: Car;
  cmd: string;
  done: number;
  total: number;
}

const RUNNING = /^Running (.+): (\d+) of (\d+)$/;

export function testRuns(plans: Plan[]): TestRun[] {
  return plans.flatMap(plan =>
    plan.cars.flatMap(car => {
      const m = RUNNING.exec(car.message);
      return m ? [{ plan, car, cmd: m[1], done: Number(m[2]), total: Number(m[3]) }] : [];
    }));
}

/** A test tab's key, also its Tabs value. */
export const testTabValue = (run: TestRun): string => `tests:${run.car.key}`;

/** "001 tests", or "001 tests, luke" when two agents on one plan are testing at once. */
export function testTabLabel(run: TestRun, runs: TestRun[]): string {
  const shared = runs.some(r => r !== run && r.plan.ordinal === run.plan.ordinal);
  return shared ? `${planId(run.plan.ordinal)} tests, ${run.car.agent.split("-")[0]}` : `${planId(run.plan.ordinal)} tests`;
}

/** Another machine's plan, named so plans with one ordinal on two machines never collide. */
export const nodePlanKey = (nodeId: string, ordinal: string): string => `${nodeId}:${ordinal}`;

/** An agent still at work: running, or stuck waiting on a person. Done and failed cars only linger on the board. */
export const isWorking = (car: Car): boolean => car.state === "running" || car.state === "stuck";
