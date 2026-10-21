import type { ReactNode } from "react";
import type { Car as CarData, ModelChoice, Plan } from "../api/types";
import { clock, fmt, shortAgent } from "./format";
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
  const cls = ["car", look.blocked && "is-blocked", readOnly && "is-readonly"].filter(Boolean).join(" ");
  return (
    <div className={cls} data-car={car.key}>
      <div className="car-top">
        {/* The tile shows the role (luke-backend reads "backend"); the full name stays the accessible name and the
            tooltip, and still contains the visible text, so voice control can say either. */}
        {readOnly ? (
          <span className="car-agent" title={car.agent}>
            <span aria-hidden="true">{shortAgent(car.agent)}</span>
            <span className="sr-only">{car.agent}</span>
          </span>
        ) : (
          <button type="button" className="car-open" aria-expanded={open} aria-label={car.agent} title={car.agent} onClick={() => onOpen(plan, car)}>
            {shortAgent(car.agent)}
          </button>
        )}
        {lock && (
          <span className="car-lock" title={lock.title} aria-label={lock.title}>
            {lock.mark}
          </span>
        )}
        {lock && plan.locked?.foreign && <span className="car-lock-note">{lock.title}</span>}
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

/**
 * The sub-agents a car has running, each a ghost of a tile beside it, faded to --subagent-opacity. The faded tiles are
 * hidden from assistive technology, which hears the same list once, at full strength, from the sr-only line: text at
 * a fifth of its contrast is a picture of a sub-agent, not something to read.
 */
export function SubagentTiles({ car }: { car: CarData }) {
  const names = car.subagents ?? [];
  if (names.length === 0) return null;
  return (
    <div className="subagents">
      <span className="sr-only">
        {car.agent} has {names.length} {names.length === 1 ? "sub-agent" : "sub-agents"} running: {names.join(", ")}
      </span>
      {names.map((name, i) => (
        <div key={`${name}-${i}`} className="car is-subagent" aria-hidden="true" title={`${name}, a sub-agent of ${car.agent}`}>
          <span className="car-agent">{shortAgent(name)}</span>
          <span className="car-model">sub-agent</span>
        </div>
      ))}
    </div>
  );
}
