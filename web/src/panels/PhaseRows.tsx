// Per-phase adapter and model rows in the idea dialog (plan 040, D10 and D11): one row per phase the plan will walk
// from its starts, each with an adapter and a model select. "Agent's default" writes nothing, and an adapter that
// cannot take an agent on this machine is listed but disabled, with the reason, so the operator sees what to fix.
import { useId } from "react";
import { modelsOf, unusable } from "../board/model";
import { DEFAULT, NONE, walked, type IdeaFrontmatter, type PhaseCatalog, type PhaseChoice } from "./frontmatter";

const titled = (phase: string) => phase.charAt(0).toUpperCase() + phase.slice(1);

function PhaseRow({ phase, catalog, choice, onChange }: {
  phase: string; catalog: PhaseCatalog; choice: PhaseChoice; onChange: (c: PhaseChoice) => void;
}) {
  const id = useId();
  const models = choice.adapter === DEFAULT ? [] : modelsOf(catalog, choice.adapter);
  return (
    <div className="phase-row" role="group" aria-labelledby={`${id}-phase`}>
      <span className="phase-name" id={`${id}-phase`}>{titled(phase)}</span>
      <select
        aria-label={`Adapter for ${phase}`} value={choice.adapter}
        onChange={(e) => onChange({ adapter: e.target.value, model: DEFAULT })}
      >
        <option value={DEFAULT}>Agent's default</option>
        {catalog.adapters.map(a => {
          const why = unusable(a);
          return <option key={a.name} value={a.name} disabled={why !== null}>{why ?? a.name}</option>;
        })}
      </select>
      <select
        aria-label={`Model for ${phase}`} value={choice.model} disabled={choice.adapter === DEFAULT}
        onChange={(e) => onChange({ ...choice, model: e.target.value })}
      >
        <option value={DEFAULT}>{choice.adapter === DEFAULT ? "Agent's default" : `${choice.adapter}'s default`}</option>
        {models.map(m => <option key={m.id} value={m.id}>{m.label}</option>)}
      </select>
    </div>
  );
}

/** One row per phase the plan walks; nothing at all before the snapshot has said which phases those are. */
export function PhaseRows({ catalog, value, onChange }: {
  catalog: PhaseCatalog; value: IdeaFrontmatter; onChange: (fm: IdeaFrontmatter) => void;
}) {
  const rows = walked(catalog, value);
  if (rows.length === 0) return null;
  const set = (phase: string, choice: PhaseChoice) => onChange({ ...value, phases: { ...value.phases, [phase]: choice } });
  const off = catalog.adapters.map(unusable).filter((why): why is string => why !== null);
  return (
    <fieldset className="phase-rows">
      <legend>Coding agent per phase</legend>
      {rows.map(({ phase }) => (
        <PhaseRow key={phase} phase={phase} catalog={catalog} choice={value.phases[phase] ?? NONE} onChange={(c) => set(phase, c)} />
      ))}
      {off.length > 0 && <p className="choice-help">Not available on this machine: {off.join("; ")}.</p>}
    </fieldset>
  );
}
