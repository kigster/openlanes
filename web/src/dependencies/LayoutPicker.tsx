import { LAYOUTS, type LayoutKey } from "./layouts";

/** One radio per arrangement, drawn as a row of pills. Picking one moves the boxes and changes nothing else. */
export function LayoutPicker({ layout, onPick }: { layout: LayoutKey; onPick: (kind: LayoutKey) => void }) {
  return (
    <fieldset className="dep-filter dep-layout">
      <legend>Layout</legend>
      {LAYOUTS.map(l => (
        <label key={l.key} title={l.hint}>
          <input type="radio" name="dep-layout" value={l.key} checked={layout === l.key} onChange={() => onPick(l.key)} />
          <span>{l.name}</span>
        </label>
      ))}
    </fieldset>
  );
}
