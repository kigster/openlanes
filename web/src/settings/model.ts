// What the form needs to know about the schema and the values, with no React in it: the panes, the paths, the edits.
import type { SettingsDocument, SettingsFieldError, SettingsSchemaNode, SettingsValues } from "../api/types";

export type Path = string[];

export interface PaneModel {
  id: string;
  title: string;
  /** Where this pane's fields live in the values; empty for the scalar pane. */
  path: Path;
  /** The leaf fields, in schema order. Nested objects are flattened into dotted paths; `label` is the path below the pane's own. */
  fields: Array<{ path: Path; node: SettingsSchemaNode; label: string }>;
  children: PaneModel[];
}

const typesOf = (node: SettingsSchemaNode): string[] => (Array.isArray(node.type) ? node.type : node.type ? [node.type] : []).filter(t => t !== "null");
export const isObjectNode = (node: SettingsSchemaNode): boolean => typesOf(node).includes("object") && node.properties !== undefined;
export const kindOf = (node: SettingsSchemaNode): "boolean" | "enum" | "number" | "integer" | "string" | "json" => {
  if (node.enum && node.enum.some(e => e !== null)) return "enum";
  const [t] = typesOf(node);
  return t === "boolean" || t === "number" || t === "integer" || t === "string" ? t : "json";
};

/** `pr_review.max` → "Pr Review Max": the config's snake_case keys, as words a person reads. */
export const titleCase = (key: string): string =>
  key.split(/[\s._-]+/).filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(" ");

/** A field's label: its path with the pane's own prefix dropped, so `commands.create.after` reads "After" under "Command: Create". */
const labelOf = (path: Path, pane: Path): string => titleCase(path.slice(pane.length).join(" "));

const leaves = (node: SettingsSchemaNode, base: Path, pane: Path = base): PaneModel["fields"] =>
  Object.entries(node.properties ?? {}).flatMap(([key, child]) =>
    isObjectNode(child) && Object.keys(child.properties ?? {}).length > 0 ? leaves(child, [...base, key], pane) : [{ path: [...base, key], node: child, label: labelOf([...base, key], pane) }],
  );

/** A pane with no field anywhere inside it (a command with no settings of its own) is left out rather than drawn empty. */
const hasContent = (pane: PaneModel): boolean => pane.fields.length > 0 || pane.children.length > 0;

/**
 * Panes in `keys` order: the top-level scalars first, then one pane per section. `commands` is left out: it mirrors every
 * CLI flag, which is the command line's interface, not the project's settings. Any `commands:` the file holds is kept
 * untouched by a save, since the draft starts from the file's own values.
 */
export function panesOf(doc: SettingsDocument): PaneModel[] {
  const props = doc.schema.properties ?? {};
  const keys = doc.keys.filter(k => props[k]);
  const scalars = keys.filter(k => !isObjectNode(props[k]));
  const panes: PaneModel[] = [];
  if (scalars.length > 0) panes.push({ id: "general", title: "General", path: [], fields: scalars.map(k => ({ path: [k], node: props[k], label: titleCase(k) })), children: [] });
  for (const key of keys.filter(k => isObjectNode(props[k]))) {
    const node = props[key];
    if (key !== "commands") panes.push({ id: key, title: titleCase(key), path: [key], fields: leaves(node, [key]), children: [] });
  }
  return panes.filter(hasContent);
}

/** The ids of every pane, sub-panes included, that holds one of `paths`: what to open so a refused field is seen. */
export const panesHolding = (panes: PaneModel[], paths: ReadonlySet<string>): string[] =>
  panes.flatMap(p => (fieldPaths(p).some(f => paths.has(f)) ? [p.id, ...panesHolding(p.children, paths)] : []));

/** The DOM id of a pane's section, which the nav's settings menu scrolls to. */
export const paneAnchor = (id: string): string => `set-pane-${id.replace(/[^A-Za-z0-9_-]+/g, "-")}`;

/** Every field path the panes show, dotted; an error at any other path has no field to sit on. */
export const shownPaths = (panes: PaneModel[]): Set<string> => new Set(panes.flatMap(fieldPaths));

/** Every dotted field path inside one pane, its sub-panes included. */
export const fieldPaths = (pane: PaneModel): string[] => [...pane.fields.map(f => f.path.join(".")), ...pane.children.flatMap(fieldPaths)];

export const getAt = (obj: unknown, path: Path): unknown => path.reduce<unknown>((acc, k) => (acc && typeof acc === "object" ? (acc as Record<string, unknown>)[k] : undefined), obj);

/** A copy of `obj` with `value` at `path`, creating the objects on the way. */
export function setAt(obj: SettingsValues, path: Path, value: unknown): SettingsValues {
  const [head, ...rest] = path;
  if (rest.length === 0) return { ...obj, [head]: value };
  const child = obj[head];
  return { ...obj, [head]: setAt(child && typeof child === "object" ? (child as SettingsValues) : {}, rest, value) };
}

/** Drops null and undefined, so "unset" is one thing however the server or an emptied field spelled it. */
export function prune(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(prune);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).filter(([, v]) => v !== null && v !== undefined).map(([k, v]) => [k, prune(v)]));
  }
  return value;
}

export const sameValues = (a: SettingsValues, b: SettingsValues): boolean => JSON.stringify(sorted(prune(a))) === JSON.stringify(sorted(prune(b)));
function sorted(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).sort(([x], [y]) => x.localeCompare(y)).map(([k, v]) => [k, sorted(v)]));
  return value;
}

/** Errors by dotted path, the first message winning. */
export const errorsByPath = (errors: SettingsFieldError[]): Map<string, string> => {
  const map = new Map<string, string>();
  for (const e of errors) if (!map.has(e.path.join("."))) map.set(e.path.join("."), e.message);
  return map;
};
