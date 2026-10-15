// The apps running on this machine (plan 012), as the Preview tabs need them: grouped by plan, one tab for each plan
// whose app has a process marked `preview: true`.
import type { AppStatus } from "../api/types";
import { planId } from "../board/format";

export type Overall = "running" | "restarting" | "failed";

/** One plan's app: the process the tab shows, and every process, in the order the runner reported them. */
export interface RunningApp {
  plan: string;
  branch: string;
  preview: AppStatus;
  processes: AppStatus[];
}

/** The list with one process's news applied: the latest wins, and `stopped` takes it off. */
export function withApp(list: AppStatus[], app: AppStatus): AppStatus[] {
  const same = (a: AppStatus) => a.plan === app.plan && a.process === app.process;
  if (app.state === "stopped") return list.filter(a => !same(a));
  return list.some(same) ? list.map(a => (same(a) ? app : a)) : [...list, app];
}

/** A tab per plan whose app has a preview process, plans in order. An app with none gets no tab (spec item 2). */
export function runningApps(list: AppStatus[]): RunningApp[] {
  const plans = [...new Set(list.map(a => a.plan))].sort();
  return plans.flatMap(plan => {
    const processes = list.filter(a => a.plan === plan && a.state !== "stopped");
    const preview = processes.find(a => a.preview);
    return preview ? [{ plan, branch: preview.branch, preview, processes }] : [];
  });
}

/** Failed if any process failed, restarting while any is on its way up, else running. */
export function overall(app: RunningApp): Overall {
  if (app.processes.some(p => p.state === "failed")) return "failed";
  if (app.processes.some(p => p.state === "starting" || p.state === "restarting")) return "restarting";
  return "running";
}

export const appTabValue = (app: RunningApp): string => `app:${app.plan}`;

/** `▶ 012 · kig/012.00-app-runner-and-preview · :11101` (M13: plan, branch and port). */
export const appTabLabel = (app: RunningApp): string => `▶ ${planId(app.plan)} · ${app.branch} · :${app.preview.port}`;

/** Every process but the previewed one: what Restart backend restarts. */
export const backend = (app: RunningApp): AppStatus[] => app.processes.filter(p => !p.preview);

/** Opens the app in a tab of its own: for an app that refuses framing, and for anyone who wants it bigger. */
export const openWindow = (url: string): void => {
  window.open(url, "_blank", "noopener");
};
