// What the form needs to know about the schema and the values, with no React in it: the panes, the paths, the edits.
import type { SettingsDocument, SettingsFieldError, SettingsSchemaNode, SettingsValues } from "../api/types";

export type Path = string[];

export interface PaneModel {
  id: string;
  title: string;
  /** Where this pane's fields live in the values; empty for the scalar pane. */
  path: Path;
  /** The leaf fields, in schema order. Nested objects are flattened into dotted paths. */
  fields: Array<{ path: Path; node: SettingsSchemaNode }>;
  children: PaneModel[];
}

const typesOf = (node: SettingsSchemaNode): string[] => (Array.isArray(node.type) ? node.type : node.type ? [node.type] : []).filter(t => t !== "null");
export const isObjectNode = (node: SettingsSchemaNode): boolean => typesOf(node).includes("object") && node.properties !== undefined;
export const kindOf = (node: SettingsSchemaNode): "boolean" | "enum" | "number" | "integer" | "string" | "json" => {
  if (node.enum && node.enum.some(e => e !== null)) return "enum";
  const [t] = typesOf(node);
  return t === "boolean" || t === "number" || t === "integer" || t === "string" ? t : "json";
};

const leaves = (node: SettingsSchemaNode, base: Path): PaneModel["fields"] =>
  Object.entries(node.properties ?? {}).flatMap(([key, child]) => (isObjectNode(child) && Object.keys(child.properties ?? {}).length > 0 ? leaves(child, [...base, key]) : [{ path: [...base, key], node: child }]));

/** Panes in `keys` order: the top-level scalars first, then one pane per section; `commands` gets a sub-pane per command. */
export function panesOf(doc: SettingsDocument): PaneModel[] {
  const props = doc.schema.properties ?? {};
  const keys = doc.keys.filter(k => props[k]);
  const scalars = keys.filter(k => !isObjectNode(props[k]));
  const panes: PaneModel[] = [];
  if (scalars.length > 0) panes.push({ id: "general", title: "General", path: [], fields: scalars.map(k => ({ path: [k], node: props[k] })), children: [] });
  for (const key of keys.filter(k => isObjectNode(props[k]))) {
    const node = props[key];
    if (key === "commands") {
      const children = Object.entries(node.properties ?? {}).map(([name, child]) => ({ id: `commands.${name}`, title: name, path: ["commands", name], fields: leaves(child, ["commands", name]), children: [] }));
      panes.push({ id: key, title: key, path: [key], fields: [], children });
    } else {
      panes.push({ id: key, title: key, path: [key], fields: leaves(node, [key]), children: [] });
    }
  }
  return panes;
}

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
