import { useId } from "react";
import type { SettingsSchemaNode } from "../api/types";
import { kindOf, type Path } from "./model";

interface Props {
  path: Path;
  node: SettingsSchemaNode;
  /** The value the file holds; null or undefined is unset. */
  value: unknown;
  /** What the project does when it is unset. */
  fallback: unknown;
  error?: string;
  onChange: (value: unknown) => void;
}

const show = (v: unknown): string => (v === null || v === undefined ? "" : typeof v === "object" ? JSON.stringify(v) : String(v));

/** One key: label, control by schema type, help line, and the server's refusal of this key if it sent one. */
export function Field({ path, node, value, fallback, error, onChange }: Props) {
  const id = useId();
  const name = path.join(".");
  const kind = kindOf(node);
  const helpId = `${id}-help`;
  const errId = `${id}-err`;
  const common = { id, name, "aria-describedby": error ? `${helpId} ${errId}` : helpId, "aria-invalid": error ? true : undefined } as const;

  let control;
  if (kind === "boolean") {
    control = <input {...common} type="checkbox" checked={Boolean(value ?? fallback)} onChange={e => onChange(e.target.checked)} />;
  } else if (kind === "enum") {
    control = (
      <select {...common} value={show(value)} onChange={e => onChange(e.target.value === "" ? null : e.target.value)}>
        <option value="">{fallback === null || fallback === undefined ? "(unset)" : `(default: ${show(fallback)})`}</option>
        {node.enum?.filter(o => o !== null).map(o => (
          <option key={String(o)} value={String(o)}>{String(o)}</option>
        ))}
      </select>
    );
  } else if (kind === "number" || kind === "integer") {
    control = (
      <input {...common} type="number" min={node.minimum} step={kind === "integer" ? 1 : "any"} value={show(value)} placeholder={show(fallback)} onChange={e => onChange(e.target.value === "" ? null : Number(e.target.value))} />
    );
  } else if (kind === "string") {
    control = <input {...common} type="text" value={show(value)} placeholder={show(fallback)} onChange={e => onChange(e.target.value === "" ? null : e.target.value)} />;
  } else {
    control = (
      <input
        {...common}
        type="text"
        value={show(value)}
        placeholder={show(fallback)}
        onChange={e => {
          const text = e.target.value;
          if (text === "") return onChange(null);
          try {
            onChange(JSON.parse(text));
          } catch {
            onChange(text);
          }
        }}
      />
    );
  }

  return (
    <div className={`set-field${error ? " is-invalid" : ""}`}>
      <label htmlFor={id}>{name}</label>
      {control}
      <p className="set-help" id={helpId}>{node.description ?? ""}</p>
      {error && <p className="set-error" id={errId} role="alert">{error}</p>}
    </div>
  );
}
