import { useId, useLayoutEffect, useRef, useState } from "react";
import type { SettingsSchemaNode } from "../api/types";
import { kindOf, type Path } from "./model";

interface Props {
  path: Path;
  /** What a person reads beside the control; the control's `name` stays the dotted path. */
  label: string;
  node: SettingsSchemaNode;
  /** The value the file holds; null or undefined is unset. */
  value: unknown;
  /** What the project does when it is unset. */
  fallback: unknown;
  error?: string;
  onChange: (value: unknown) => void;
}

const show = (v: unknown): string => (v === null || v === undefined ? "" : typeof v === "object" ? JSON.stringify(v) : String(v));
const isSet = (v: unknown): boolean => v !== null && v !== undefined;

/** Free text is a textarea that wraps and grows with what is typed, rather than one line scrolling sideways. */
const isProse = (path: Path): boolean => path[path.length - 1] === "description";

/** Grows a textarea to its content, so a long description is read whole rather than scrolled inside a box. */
function fit(el: HTMLTextAreaElement | null): void {
  if (!el) return;
  el.style.height = "auto";
  el.style.height = `${el.scrollHeight + 2}px`;
}

/**
 * One key: label, control by schema type, help line, and the server's refusal of this key if it sent one. An unset key
 * shows its default as the control's value, so the box reads what the project will do; typing the default back, or
 * emptying the box, leaves the key unset, so a save never writes a default into the file.
 */
export function Field({ path, label, node, value, fallback, error, onChange }: Props) {
  const id = useId();
  const name = path.join(".");
  const kind = kindOf(node);
  const helpId = `${id}-help`;
  const errId = `${id}-err`;
  const common = { id, name, "aria-describedby": error ? `${helpId} ${errId}` : helpId, "aria-invalid": error ? true : undefined } as const;
  // The text the person sees, kept here: emptying a box must leave it empty, not snap the default back in under the cursor.
  const [text, setText] = useState(() => show(isSet(value) ? value : fallback));
  const area = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => fit(area.current), [text]);

  /** Sends what `raw` means: unset when empty or the default, else `parse(raw)`. */
  const edit = (raw: string, parse: (raw: string) => unknown) => {
    setText(raw);
    onChange(raw === "" || (isSet(fallback) && raw === show(fallback)) ? null : parse(raw));
  };

  let control;
  if (kind === "boolean") {
    control = <input {...common} type="checkbox" checked={Boolean(value ?? fallback)} onChange={e => onChange(e.target.checked === Boolean(fallback) ? null : e.target.checked)} />;
  } else if (kind === "enum") {
    const options = node.enum?.filter(o => o !== null) ?? [];
    const hasDefault = options.some(o => String(o) === show(fallback));
    control = (
      <select {...common} value={show(isSet(value) ? value : hasDefault ? fallback : null)} onChange={e => onChange(e.target.value === "" || e.target.value === show(fallback) ? null : e.target.value)}>
        {!hasDefault && <option value="">(unset)</option>}
        {options.map(o => (
          <option key={String(o)} value={String(o)}>{String(o) === show(fallback) ? `${String(o)} (default)` : String(o)}</option>
        ))}
      </select>
    );
  } else if (kind === "number" || kind === "integer") {
    control = <input {...common} type="number" min={node.minimum} step={kind === "integer" ? 1 : "any"} value={text} onChange={e => edit(e.target.value, Number)} />;
  } else if (kind === "string" && isProse(path)) {
    control = <textarea {...common} ref={area} rows={2} value={text} onChange={e => edit(e.target.value, raw => raw)} />;
  } else if (kind === "string") {
    control = <input {...common} type="text" value={text} onChange={e => edit(e.target.value, raw => raw)} />;
  } else {
    const json = (raw: string): unknown => {
      try {
        return JSON.parse(raw);
      } catch {
        return raw;
      }
    };
    control = <input {...common} type="text" value={text} onChange={e => edit(e.target.value, json)} />;
  }

  // A checkbox goes before its label, on one line; every other control sits to the right of its label.
  const check = kind === "boolean";
  return (
    <div className={`set-field${check ? " is-check" : ""}${error ? " is-invalid" : ""}`}>
      {check ? control : <label htmlFor={id}>{label}</label>}
      {check ? <label htmlFor={id}>{label}</label> : control}
      <p className="set-help" id={helpId}>{node.description ?? ""}</p>
      {error && <p className="set-error" id={errId} role="alert">{error}</p>}
    </div>
  );
}
