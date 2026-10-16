import { useCallback, useEffect, useRef } from "react";
import { AnimatePresence, motion } from "motion/react";
import type { Plan, Snapshot, Station } from "../api/types";
import { planId, redactUrl, span, who } from "../board/format";
import { hasRequest, isApproved, isMerged, pillState } from "../board/model";
import { MERGED_STAYS_MS, type GonePlan } from "../board/useLifecycle";

export interface StatusBarProps {
  /** The Redis the engine keeps plan claims and run state in, from its snapshot; null or absent from an older engine. */
  redisUrl?: string | null;
  plans: Plan[];
  stations: Station[];
  others: Snapshot[];
  gone: ReadonlyMap<string, GonePlan>;
  offBar: ReadonlySet<string>;
  finishOrder: ReadonlyMap<string, number>;
  /** The plan whose unblock widget is open. */
  unblocking: string | null;
  /** A red pill with a question or an interrupt: toggles the unblock widget. */
  onToggleUnblock: (plan: Plan) => void;
  /** Any other pill of ours: show the plan on the Board. */
  onShowPlan: (plan: Plan) => void;
  /** Another machine's pill: open that machine's tab. */
  onOpenMachine: (nodeId: string) => void;
  /** Takes a purple pill off an overflowing bar. */
  onDropGone: (ordinal: string) => void;
}

interface Entry {
  plan: Plan;
  gone: boolean;
  finished: boolean;
}

const FADE = { duration: 0.3 };
const SLIDE = { duration: 0.45, ease: [0.2, 0.7, 0.2, 1] as const };

/**
 * The status bar along the bottom: one pill per plan of ours (working and blocked first in plan order, finished ones
 * after a divider in the order they finished), other machines' plans at the right end, and the summary.
 */
export function StatusBar(props: StatusBarProps) {
  const { redisUrl, plans, stations, others, gone, offBar, finishOrder, unblocking, onToggleUnblock, onShowPlan, onOpenMachine, onDropGone } = props;
  const list = useRef<HTMLOListElement>(null);

  const live = plans.filter(p => !gone.has(p.ordinal));
  const entries: Entry[] = [
    ...live.map(plan => ({ plan, gone: false, finished: isApproved(plan) || isMerged(plan) })),
    ...[...gone.values()].filter(g => !offBar.has(g.plan.ordinal)).map(g => ({ plan: g.plan, gone: true, finished: true })),
  ];
  const working = entries.filter(e => !e.finished).sort((a, b) => a.plan.ordinal.localeCompare(b.plan.ordinal));
  const order = (e: Entry) => finishOrder.get(e.plan.ordinal) ?? Number.MAX_SAFE_INTEGER;
  const finished = entries.filter(e => e.finished).sort((a, b) => order(a) - order(b) || a.plan.ordinal.localeCompare(b.plan.ordinal));

  // When the bar runs out of room, merged plans leave it, oldest first, once each has been shown for a while.
  const latest = useRef({ gone, offBar, onDropGone });
  latest.current = { gone, offBar, onDropGone };
  const trim = useCallback(() => {
    const el = list.current;
    if (!el || el.scrollWidth <= el.clientWidth + 1) return;
    const now = Date.now();
    const { gone: g, offBar: off, onDropGone: drop } = latest.current;
    const leaving = [...g.values()]
      .filter(x => !off.has(x.plan.ordinal) && now - x.at >= MERGED_STAYS_MS)
      .sort((a, b) => a.at - b.at)[0];
    if (leaving) drop(leaving.plan.ordinal);
  }, []);
  useEffect(trim);
  useEffect(() => {
    const id = setInterval(trim, 15_000);
    return () => clearInterval(id);
  }, [trim]);

  const ours = [...plans.filter(p => !gone.has(p.ordinal)), ...[...gone.values()].map(g => g.plan)];
  const merged = ours.filter(isMerged).length;
  const ready = ours.filter(isApproved).length;
  const blocked = live.filter(p => pillState(p, stations).blocked).length;

  // Each pill's name starts with what it shows, "005 1h 38m", for voice control (label-content-name-mismatch); the
  // space between the id and the time keeps that text "005 1h 38m" in the DOM, not "0051h 38m".
  const pill = ({ plan, gone: isGone }: Entry) => {
    const st = pillState(plan, stations, isGone);
    const request = st.blocked && hasRequest(plan);
    const id = planId(plan.ordinal);
    return (
      <motion.li key={plan.ordinal} layout="position" transition={SLIDE} exit={{ opacity: 0, transition: FADE }}>
        <button
          type="button"
          className={`pill ${st.cls}`.trim()}
          data-plan={plan.ordinal}
          title={`${id} ${plan.title}: ${st.say}`}
          aria-label={`${id} ${span(plan.elapsed)}, ${st.say}`}
          aria-expanded={request ? unblocking === plan.ordinal : undefined}
          onClick={() => (request ? onToggleUnblock(plan) : onShowPlan(plan))}
        >
          <span className="pill-mark" aria-hidden="true">
            {st.mark}
          </span>
          <span className="pill-text">
            <span className="pill-id">{id}</span>{" "}
            <span className="pill-time">{span(plan.elapsed)}</span>
          </span>
        </button>
      </motion.li>
    );
  };

  return (
    <footer className="statusbar" aria-labelledby="statusbar-title">
      <h2 id="statusbar-title">Plans</h2>
      <ol className="pills" ref={list}>
        <AnimatePresence initial={false}>
          {working.map(pill)}
          {finished.length > 0 && <motion.li key="divider" layout="position" className="divider" aria-hidden="true" />}
          {finished.map(pill)}
        </AnimatePresence>
      </ol>
      <ol className="pills pills-theirs" aria-label="Plans on other machines, read only">
        {others.flatMap(their =>
          their.plans.map(plan => {
            const merged = isMerged(plan);
            const done = isApproved(plan);
            const at = stations.find(s => s.key === plan.station)?.label ?? plan.station;
            const id = planId(plan.ordinal);
            const state = merged ? "merged on GitHub, complete" : done ? "reviewed, ready to merge" : `at ${at}`;
            return (
              <li key={`${their.node.id}-${plan.ordinal}`}>
                <button
                  type="button"
                  className={`pill${merged ? " is-gone" : done ? " is-done" : ""}`}
                  title={`${id} ${plan.title}: on ${who(their.node)}, ${state}. Read only.`}
                  aria-label={`${id} ${span(plan.elapsed)}, on ${who(their.node)}, read only, ${state}`}
                  onClick={() => onOpenMachine(their.node.id)}
                >
                  <span className="pill-mark" aria-hidden="true">
                    {merged ? "✅" : done ? "✓" : "🖥️"}
                  </span>
                  <span className="pill-text">
                    <span className="pill-id">{id}</span>{" "}
                    <span className="pill-time">{span(plan.elapsed)}</span>
                  </span>
                </button>
              </li>
            );
          }),
        )}
      </ol>
      <p className="statusbar-sum">
        {merged} merged, {ready} ready to merge, {blocked} blocked
      </p>
      {redisUrl && (
        <p className="statusbar-redis" title="The Redis this machine's engine keeps plan claims, locks and run state in">
          Redis <code>{redactUrl(redisUrl)}</code>
        </p>
      )}
    </footer>
  );
}
