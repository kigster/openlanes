import { useMemo } from "react";
import * as Tooltip from "@radix-ui/react-tooltip";
import { useDependencies } from "../api/dependencies";
import { DependencyFlow } from "./DependencyFlow";
import { StateFilter } from "./StateFilter";
import { visible } from "./model";
import { useStateFilter } from "./useStateFilter";
import "./dependencies.css";

/** The plan graph: a box per plan, an arrow per depends_on: edge, drawn by React Flow once the filter has chosen. */
export function DependenciesPage() {
  const { data, error, isLoading } = useDependencies();
  const { checked, toggle } = useStateFilter(data?.states ?? []);
  const shown = useMemo(() => (data ? visible(data, checked) : null), [data, checked]);

  if (error) return <main className="dep-page is-error" role="alert">Could not load the plan dependencies: {error.message}</main>;
  if (isLoading || !data || !shown) return <main className="dep-page" aria-busy="true">Loading plan dependencies…</main>;

  return (
    <main className="dep-page">
      <h1>Plan dependencies</h1>
      <StateFilter states={data.states} checked={checked} onToggle={toggle} />
      <Tooltip.Provider delayDuration={0}>
        {shown.plans.length === 0 ? <p className="dep-empty">No plans in the checked states.</p> : <DependencyFlow graph={data} shown={shown} />}
      </Tooltip.Provider>
    </main>
  );
}
