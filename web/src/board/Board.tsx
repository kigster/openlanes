import type { CSSProperties, ReactNode } from "react";
import type { Board as BoardData, Snapshot, Station } from "../api/types";
import { PlanRow, type CarHandlers } from "./PlanRow";
import { active, lastSeen, who } from "./format";
import { dagBreak, nodePlanKey } from "./model";
import "./board.css";

/** The station columns: StateMachine::SPINE, each with the agents whose `handles:` names it. */
export function Stations({ stations }: { stations: Station[] }) {
  return (
    <div className="stations">
      <span />
      {stations.map(s => (
        <div className="station-name" key={s.key}>
          {s.label}
          <span className="station-agent">{s.agents.join(" + ") || " "}</span>
        </div>
      ))}
    </div>
  );
}

function Inner({ stations, children }: { stations: Station[]; children: ReactNode }) {
  return (
    <div className="board-inner" style={{ "--stations": stations.length } as CSSProperties}>
      <Stations stations={stations} />
      {children}
    </div>
  );
}

/** A band in the highlight colour opening one machine's rows in the merged board. */
export function MachineHead({ name, facts }: { name: string; facts: string[] }) {
  return (
    <div className="machine-head">
      <h2>{name}</h2>
      <p>
        {facts.map(f => (
          <span key={f}>{f}</span>
        ))}
      </p>
    </div>
  );
}

/** Other machines' merged rows, keyed by nodePlanKey: fading now, or gone. */
export interface TheirLifecycle {
  retiring: ReadonlySet<string>;
  gone: ReadonlyMap<string, unknown>;
}

const NOTHING: TheirLifecycle = { retiring: new Set(), gone: new Map() };

/** Their plans still on the board: a merged one stays ten seconds, fades, then leaves, as ours do. */
const showing = (s: Snapshot, life: TheirLifecycle) => s.plans.filter(p => !life.gone.has(nodePlanKey(s.node.id, p.ordinal)));

interface BoardProps extends CarHandlers {
  board: BoardData;
  /** All machines: every other machine's rows under ours, read only. */
  merged: boolean;
  /** Merged rows fading out right now. */
  retiring: ReadonlySet<string>;
  /** Merged rows that have left the board. */
  gone: ReadonlyMap<string, unknown>;
  /** The same for other machines' rows. */
  theirs?: TheirLifecycle;
  /** Hide Inactive is on: only lanes with an agent running are drawn, here and under other machines. */
  hideInactive?: boolean;
}

/** The transit board: our plans, and with All machines on, everyone else's under ours. */
export function Board({ board, merged, retiring, gone, theirs = NOTHING, hideInactive = false, ...cars }: BoardProps) {
  const { me, others } = board;
  const all = me.plans.filter(p => !gone.has(p.ordinal));
  const ours = hideInactive ? all.filter(active) : all;
  const hidden = all.length - ours.length;
  return (
    <Inner stations={me.stations}>
      {merged && <MachineHead name={who(me.node)} facts={[me.node.ip, `${ours.length} plans`, "this machine"].filter((f): f is string => f !== null)} />}
      {all.length === 0 && !merged && <p className="board-empty">No plans in this run yet. Add one from Action.</p>}
      {ours.map((plan, i) => (
        <PlanRow
          key={plan.ordinal} plan={plan} stations={me.stations} adapters={me.adapters} retiring={retiring.has(plan.ordinal)}
          dagBreak={dagBreak(ours, i)} {...cars}
        />
      ))}
      {/* Said in words, so an empty or short board is never mistaken for an idle factory. */}
      {hidden > 0 && (
        <p className="board-empty board-hidden" role="status">
          {ours.length === 0 ? "No lane has an agent running. " : ""}
          {hidden} inactive lane{hidden === 1 ? "" : "s"} hidden. Turn off Hide Inactive to see {hidden === 1 ? "it" : "them"}.
        </p>
      )}
      {merged &&
        others.map(their => (
          <MachineRows key={their.node.id} their={their} me={me} life={theirs} hideInactive={hideInactive} />
        ))}
    </Inner>
  );
}

function MachineRows({ their, me, life, hideInactive = false }: { their: Snapshot; me: Snapshot; life: TheirLifecycle; hideInactive?: boolean }) {
  const plans = showing(their, life).filter(plan => !hideInactive || active(plan));
  return (
    <>
      <MachineHead
        name={who(their.node)}
        facts={[their.node.ip, `${plans.length} plans`, "read only", `last seen ${lastSeen(their, me)}s ago`].filter((f): f is string => f !== null)}
      />
      {plans.map((plan, i) => (
        <PlanRow
          key={plan.ordinal} plan={plan} stations={their.stations} adapters={their.adapters} owner={their.node} faded
          dagBreak={dagBreak(plans, i)}
          retiring={life.retiring.has(nodePlanKey(their.node.id, plan.ordinal))}
        />
      ))}
    </>
  );
}

/** One other machine's board, read only, for its tab. */
export function MachineBoard({ their, me, life = NOTHING }: { their: Snapshot; me: Snapshot; life?: TheirLifecycle }) {
  return (
    <>
      <p className="machine-note">
        Read only. <strong>{who(their.node)}</strong>
        {their.node.ip ? ` (${their.node.ip})` : ""} is working on these in {their.node.checkout}; this machine will not start
        them. Last seen {lastSeen(their, me)}s ago.
      </p>
      <Inner stations={their.stations}>
        {showing(their, life).map(plan => (
          <PlanRow
            key={plan.ordinal} plan={plan} stations={their.stations} adapters={their.adapters} owner={their.node}
            retiring={life.retiring.has(nodePlanKey(their.node.id, plan.ordinal))}
          />
        ))}
      </Inner>
    </>
  );
}
