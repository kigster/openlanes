import { useState, type ReactNode } from "react";
import { Field } from "./Field";
import { errorsByPath, getAt, type PaneModel } from "./model";
import type { SettingsValues } from "../api/types";

interface Props {
  pane: PaneModel;
  values: SettingsValues;
  defaults: SettingsValues;
  errors: ReturnType<typeof errorsByPath>;
  onChange: (path: string[], value: unknown) => void;
  /** Sub-panes sit inside their parent's body. */
  nested?: boolean;
}

/** A collapsible group of fields. Open on load; the −/+ button folds it. */
export function Pane({ pane, values, defaults, errors, onChange, nested = false }: Props) {
  const [open, setOpen] = useState(true);
  const body: ReactNode = (
    <>
      {pane.fields.map(f => (
        <Field key={f.path.join(".")} path={f.path} node={f.node} value={getAt(values, f.path)} fallback={getAt(defaults, f.path)} error={errors.get(f.path.join("."))} onChange={v => onChange(f.path, v)} />
      ))}
      {pane.children.map(c => (
        <Pane key={c.id} pane={c} values={values} defaults={defaults} errors={errors} onChange={onChange} nested />
      ))}
    </>
  );
  const Heading = nested ? "h3" : "h2";
  return (
    <section className={`set-pane${nested ? " is-nested" : ""}`} aria-label={pane.title}>
      <Heading>
        <button type="button" className="set-toggle" aria-expanded={open} aria-label={`${open ? "Collapse" : "Open"} ${pane.title}`} onClick={() => setOpen(o => !o)}>
          {open ? "−" : "+"}
        </button>
        {pane.title}
      </Heading>
      {open && <div className="set-body">{body}</div>}
    </section>
  );
}
