import type { ReactNode } from "react";
import type { Car as CarData, ModelChoice, Plan } from "../api/types";
import { clock, fmt } from "./format";
import { carLook, lockMark, modelLabel } from "./model";

interface CarProps {
  plan: Plan;
  car: CarData;
  models: ModelChoice[];
  /** Its drawer is open. */
  open?: boolean;
  /** Absent on other machines' boards: their cars are plain cards with the model as text. */
  onOpen?: (plan: Plan, car: CarData) => void;
  /** The model dropdown (ModelSelect from src/panels), on a layer above the card's hit area. */
  modelSlot?: ReactNode;
}

/**
 * One agent at work, hanging under its plan's station. The agent's name is the button that opens the drawer, and its
 * hit area covers the whole card; a blocked car swaps its activity line for the reason it is red.
 */
export function Car({ plan, car, models, open = false, onOpen, modelSlot }: CarProps) {
  const look = carLook(plan, car);
  const readOnly = !onOpen;
  const lock = lockMark(plan);
  // At most three lines: more would crowd the 248px tile, and the count itself is in the label.
  const fanned = car.subagents > 0 ? Math.min(car.subagents, 3) : 0;
  const fanLabel = fanned ? `${car.subagents} sub-agent${car.subagents === 1 ? "" : "s"} running` : undefined;
  const cls = ["car", look.blocked && "is-blocked", readOnly && "is-readonly", fanned > 0 && "car-fanned"]
    .filter(Boolean)
    .join(" ");
  return (
    <div className={cls} data-car={car.key} title={fanLabel} aria-label={fanLabel}>
      {Array.from({ length: fanned }, (_, i) => (
        <span key={i} className="car-stack-line" aria-hidden="true" style={{ "--n": i } as React.CSSProperties} />
      ))}
      <div className="car-top">
        {readOnly ? (
          <span className="car-agent">{car.agent}</span>
        ) : (
          <button type="button" className="car-open" aria-expanded={open} onClick={() => onOpen(plan, car)}>
            {car.agent}
          </button>
        )}
        {lock && (
          <span className="car-lock" title={lock.title} aria-label={lock.title}>
            {lock.mark}
          </span>
        )}
        {look.label ? (
          <span className="car-model">{look.label}</span>
        ) : readOnly || !modelSlot ? (
          <span className="car-model">{modelLabel(models, car.model)}</span>
        ) : (
          <span className="car-slot">{modelSlot}</span>
        )}
      </div>
      <div className="car-activity" title={look.blocked ? look.activity : undefined}>
        {look.activity}
      </div>
      <div className="car-stats">
        <span title="Tokens in">
          ↑ <b>{fmt(car.up)}</b>
        </span>
        <span title="Tokens out">
          ↓ <b>{fmt(car.down)}</b>
        </span>
        <span>{clock(car.elapsed)}</span>
      </div>
    </div>
  );
}

/** The car an interrupted plan shows in place of its agents until someone keeps or discards the work. */
export function InterruptedCar({ agent }: { agent: string }) {
  return (
    <div className="car is-queued is-blocked">
      <div className="car-top">
        <span className="car-agent">{agent}</span>
        <span className="car-model">interrupted</span>
      </div>
      <div className="car-activity">You interrupted it. Keep its work or discard it in Needs you.</div>
    </div>
  );
}
