import type { ReactNode } from "react";
import { FoldToggle } from "../shell/FoldToggle";
import { Field } from "./Field";
import { errorsByPath, getAt, paneAnchor, type PaneModel } from "./model";
import type { SettingsValues } from "../api/types";

interface Props {
  pane: PaneModel;
  values: SettingsValues;
  defaults: SettingsValues;
  errors: ReturnType<typeof errorsByPath>;
  onChange: (path: string[], value: unknown) => void;
  /** Which panes are open, by id; the page keeps it, so a save that remounts the form leaves them as they were. */
  openIds: ReadonlySet<string>;
  onToggle: (id: string, open: boolean) => void;
  /** Sub-panes sit inside their parent's body. */
  nested?: boolean;
}

/** A collapsible group of fields, folded until its −/+ button opens it. */
export function Pane({ pane, values, defaults, errors, onChange, openIds, onToggle, nested = false }: Props) {
  const open = openIds.has(pane.id);
  const body: ReactNode = (
    <>
      {pane.fields.map(f => (
        <Field key={f.path.join(".")} path={f.path} label={f.label} node={f.node} value={getAt(values, f.path)} fallback={getAt(defaults, f.path)} error={errors.get(f.path.join("."))} onChange={v => onChange(f.path, v)} />
      ))}
      {pane.children.map(c => (
        <Pane key={c.id} pane={c} values={values} defaults={defaults} errors={errors} onChange={onChange} openIds={openIds} onToggle={onToggle} nested />
      ))}
    </>
  );
  const classes = ["set-pane", nested && "is-nested", pane.children.length > 0 && "has-panes"].filter(Boolean).join(" ");
  return (
    <section id={paneAnchor(pane.id)} className={classes} aria-label={pane.title}>
      <h2>
        <FoldToggle open={open} title={pane.title} onToggle={() => onToggle(pane.id, !open)} />
        {pane.title}
      </h2>
      {open && <div className="set-body">{body}</div>}
    </section>
  );
}
