import type { DependencyState } from "../api/types";

/** One checkbox per state, in the order the endpoint sent them. */
export function StateFilter({ states, checked, onToggle }: { states: DependencyState[]; checked: Set<string>; onToggle: (key: string) => void }) {
  return (
    <fieldset className="dep-filter">
      <legend>States shown</legend>
      {states.map(s => (
        <label key={s.key}>
          <input type="checkbox" checked={checked.has(s.key)} onChange={() => onToggle(s.key)} />
          <span>
            {s.emoji} {s.name}
          </span>
        </label>
      ))}
    </fieldset>
  );
}
