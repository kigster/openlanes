import { useMemo } from "react";
import * as Tooltip from "@radix-ui/react-tooltip";
import { useDependencies } from "../api/dependencies";
import { BridgeEdge } from "./BridgeEdge";
import { PlanNode } from "./PlanNode";
import { StateFilter } from "./StateFilter";
import { NODE_HEIGHT, NODE_WIDTH, curve, layout, visible } from "./model";
import { useStateFilter } from "./useStateFilter";
import "./dependencies.css";

/** The plan graph: a box per plan, an arrow per depends_on: edge. `stamp` changes when the board says a plan moved. */
export function DependenciesPage({ stamp = "" }: { stamp?: string }) {
  const { data, error, isLoading } = useDependencies(stamp);
  const stateKeys = useMemo(() => (data?.states ?? []).map(s => s.key), [data]);
  const { checked, toggle } = useStateFilter(stateKeys);
  // Laid out again on every filter change, so the boxes close up around the plans that are gone.
  const shown = useMemo(() => (data ? visible(data, checked) : null), [data, checked]);
  const placed = useMemo(
    () => (shown ? layout(shown.plans, [...shown.edges, ...shown.bridges]) : []),
    [shown],
  );

  if (error) return <main className="dep-page is-error" role="alert">Could not load the plan dependencies: {error.message}</main>;
  if (isLoading || !data || !shown) return <main className="dep-page" aria-busy="true">Loading plan dependencies…</main>;

  const at = new Map(placed.map(p => [p.plan.ordinal, p]));
  const out = (o: string) => ({ x: at.get(o)!.x + NODE_WIDTH, y: at.get(o)!.y + NODE_HEIGHT / 2 });
  const into = (o: string) => ({ x: at.get(o)!.x, y: at.get(o)!.y + NODE_HEIGHT / 2 });
  const title = new Map(data.plans.map(p => [p.ordinal, p.title]));
  const states = new Map(data.states.map(s => [s.key, s]));
  const width = Math.max(0, ...placed.map(p => p.x + NODE_WIDTH)) + 24;
  const height = Math.max(0, ...placed.map(p => p.y + NODE_HEIGHT)) + 24;

  return (
    <main className="dep-page">
      <h1>Plan dependencies</h1>
      <StateFilter states={data.states} checked={checked} onToggle={toggle} />
      <Tooltip.Provider delayDuration={0}>
        {placed.length === 0 ? (
          <p className="dep-empty">No plans in the checked states.</p>
        ) : (
          <div className="dep-canvas" style={{ width, height }} data-testid="dep-canvas">
            <svg width={width} height={height} aria-hidden={false} role="group" aria-label="Dependencies">
              <defs>
                <marker id="dep-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                  <path d="M0,0 L10,5 L0,10 z" fill="currentColor" />
                </marker>
              </defs>
              {shown.edges.map(e => (
                <path key={`${e.from}>${e.to}`} className="dep-edge" data-from={e.from} data-to={e.to} d={curve(out(e.from), into(e.to))} markerEnd="url(#dep-arrow)" />
              ))}
              {shown.bridges.map(b => (
                <BridgeEdge key={`${b.from}>${b.to}`} bridge={b} from={out(b.from)} to={into(b.to)} names={b.via.map(o => `${o} ${title.get(o) ?? ""}`.trim())} />
              ))}
            </svg>
            {placed.map(p => (
              <PlanNode key={p.plan.ordinal} plan={p.plan} state={states.get(p.plan.state)} x={p.x} y={p.y} />
            ))}
          </div>
        )}
      </Tooltip.Provider>
    </main>
  );
}
