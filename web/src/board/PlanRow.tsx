import { useEffect, type CSSProperties, type ReactNode } from "react";
import { useAnimate, useReducedMotion } from "motion/react";
import type { Car as CarData, ModelChoice, Node, Plan, Station } from "../api/types";
import { Car, InterruptedCar, SubagentTiles } from "./Car";
import { Terminus } from "./Terminus";
import { fmt, planId, who } from "./format";
import { LANES, rowColors, rowDomId, routeOf } from "./model";
import { FADE_MS } from "./useLifecycle";

export interface CarHandlers {
  /** The car whose drawer is open, by Car.key. */
  openCar?: string | null;
  onOpenCar?: (plan: Plan, car: CarData) => void;
  /** The model dropdown for one car: ModelSelect from src/panels. */
  renderModel?: (plan: Plan, car: CarData) => ReactNode;
}

interface PlanRowProps extends CarHandlers {
  plan: Plan;
  stations: Station[];
  models: ModelChoice[];
  /** Set on another machine's plan: no controls, and the meta line names the machine. */
  owner?: Node;
  /** Their rows under ours in the merged board, at 85% opacity. */
  faded?: boolean;
  /** A merged row on its way out: it fades, then folds away. */
  retiring?: boolean;
}

const vars = (v: Record<string, string | number>): CSSProperties => v as CSSProperties;

/**
 * Mail between the plan's agents that nobody has acked yet: a warning for a person, never an input to a round (D2).
 * Nothing at zero, so a quiet plan's meta line stays as it was.
 */
export function UnackedBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  const said = `${count} unacked ${count === 1 ? "message" : "messages"}`;
  return (
    <span className="unacked is-warning" title={`${said} between this plan's agents`}>
      <span aria-hidden="true">✉ {count}</span>
      <span className="sr-only">{said}</span>
    </span>
  );
}

/** One plan as its own horizontal line through the station columns, with its agents hanging under its station. */
export function PlanRow({ plan, stations, models, owner, faded = false, retiring = false, openCar, onOpenCar, renderModel }: PlanRowProps) {
  const lane = LANES[plan.lane];
  const route = routeOf(plan, stations);
  const { color, bg } = rowColors(plan);
  const readOnly = Boolean(owner);
  const [scope, animate] = useAnimate<HTMLElement>();
  const reduced = useReducedMotion();

  useEffect(() => {
    const row = scope.current;
    if (!retiring || reduced || !row) return;
    // Fade first, then fold the height away, so the rows below close the gap slowly (the mockup's retire()). The padding
    // is read rather than assumed, because a narrow lane has less of it and would otherwise grow before it shrank.
    const h = `${row.offsetHeight}px`;
    const { paddingTop: top, paddingBottom: bottom } = getComputedStyle(row);
    void animate(
      row,
      { opacity: [1, 0, 0], height: [h, h, "0px"], paddingTop: [top, top, "0px"], paddingBottom: [bottom, bottom, "0px"] },
      { duration: FADE_MS / 1000, times: [0, 0.6, 1], ease: "easeInOut" },
    );
  }, [retiring, reduced, animate, scope]);

  const atPr = stations[route.at]?.key === "pr";
  let cars: ReactNode;
  if (atPr && plan.pr) {
    cars = <Terminus pr={plan.pr} />;
  } else if (plan.interrupted && !readOnly) {
    cars = <InterruptedCar agent={plan.interrupted.agent} />;
  } else {
    cars = (
      <>
        {plan.cars.map(car => (
          // A car and the sub-agents it started share one line, so each ghost tile sits beside the agent that owns it.
          <div key={car.key} className="car-group">
            <Car
              plan={plan}
              car={car}
              models={models}
              open={openCar === car.key}
              onOpen={readOnly ? undefined : onOpenCar}
              modelSlot={readOnly ? undefined : renderModel?.(plan, car)}
            />
            <SubagentTiles car={car} />
          </div>
        ))}
        {plan.pr && <Terminus pr={plan.pr} />}
      </>
    );
  }

  const cls = ["plan", faded && "is-theirs", retiring && "is-retiring"].filter(Boolean).join(" ");
  return (
    <article
      ref={scope}
      className={cls}
      id={readOnly ? undefined : rowDomId(plan.ordinal)}
      data-plan={plan.ordinal}
      style={vars({ "--lane-color": color, "--lane-bg": bg })}
      aria-label={faded && owner ? `${planId(plan.ordinal)} ${plan.title}, on ${who(owner)}, read only` : undefined}
    >
      <div className="plan-head">
        <div className="plan-id">
          {planId(plan.ordinal)}
          <span className="plan-status" role="img" aria-label={plan.status.label} title={plan.status.label}>{plan.status.emoji}</span>
        </div>
        <h3 className="plan-title">{plan.title}</h3>
        <div className="plan-meta">
          <span className="lane">{lane.label}</span>
          <UnackedBadge count={plan.unacked} />
          {owner ? (
            <span>on {who(owner)}</span>
          ) : (
            <>
              <span title="Tokens in">↑ <span>{fmt(plan.up)}</span></span>
              <span title="Tokens out">↓ <span>{fmt(plan.down)}</span></span>
            </>
          )}
        </div>
      </div>
      <div className="route">
        <div className="track" aria-hidden="true">
          {route.segs.map((seg, i) => (
            <span key={`seg-${i}`} className={`seg${seg === "ahead" ? "" : ` is-${seg}`}`} style={vars({ "--i": i })} />
          ))}
          {route.stops.map((stop, i) => (
            <span key={`stop-${i}`} className={`stop${stop === "ahead" ? "" : ` is-${stop}`}`} style={vars({ "--i": i })} />
          ))}
        </div>
        <div className={`cars${route.late ? " is-late" : ""}`} style={vars({ "--col": route.at })}>
          {cars}
        </div>
      </div>
    </article>
  );
}
