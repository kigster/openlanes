import { useMemo, useState } from "react";
import * as Tooltip from "@radix-ui/react-tooltip";
import { useDependencies } from "../api/dependencies";
import { DependencyFlow } from "./DependencyFlow";
import { LayoutPicker } from "./LayoutPicker";
import { StateFilter } from "./StateFilter";
import { visible } from "./model";
import { useLayout } from "./useLayout";
import { useStateFilter } from "./useStateFilter";
import "./dependencies.css";

/** The plan graph: a box per plan, an arrow per depends_on: edge, drawn by React Flow once the filter has chosen. */
export function DependenciesPage() {
  const { data, error, isLoading } = useDependencies();
  const { checked, toggle } = useStateFilter(data?.states ?? []);
  const { layout, pick } = useLayout();
  // Folded on every visit: the legend is something to look up, and the graph is what the page is for.
  const [legend, setLegend] = useState(false);
  const shown = useMemo(() => (data ? visible(data, checked) : null), [data, checked]);

  if (error) return <main className="dep-page is-error" role="alert">Could not load the plan dependencies: {error.message}</main>;
  if (isLoading || !data || !shown) return <main className="dep-page" aria-busy="true">Loading plan dependencies…</main>;

  return (
    <main className="dep-page">
      <h1>Plan dependencies</h1>
      <div className="dep-controls">
        <button
          type="button" className="btn dep-legend-toggle" aria-expanded={legend} aria-controls="dep-legend"
          title="What each state's emoji means, and which states are drawn" onClick={() => setLegend(open => !open)}
        >
          States legend <span aria-hidden="true">{legend ? "▴" : "▾"}</span>
          {/* Said while folded too, so a filter nobody can see is never mistaken for the whole graph. */}
          <span className="dep-legend-count">
            {checked.size} of {data.states.length} shown
          </span>
        </button>
        <LayoutPicker layout={layout} onPick={pick} />
      </div>
      <div id="dep-legend" hidden={!legend}>
        <StateFilter states={data.states} checked={checked} onToggle={toggle} />
      </div>
      <Tooltip.Provider delayDuration={0}>
        {shown.plans.length === 0 ? <p className="dep-empty">No plans in the checked states.</p> : <DependencyFlow graph={data} shown={shown} layout={layout} />}
      </Tooltip.Provider>
    </main>
  );
}
