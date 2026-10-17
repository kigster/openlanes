// The page's door to a plan's markdown files (plan 017, contract.md "Plan files"). Reads carry the file's ETag, which
// a save sends back as If-Match, so a file rewritten behind the popup is refused instead of overwritten.
import { ApiError, getSession, resetSession } from "./client";

/** A refusal from the files routes. `reason` is the server's own `error` text when it sent one. */
export class PlanFileError extends ApiError {
  readonly reason: string | null;
  constructor(message: string, status: number, reason: string | null) {
    super(message, status);
    this.name = "PlanFileError";
    this.reason = reason;
  }
  /** The file changed on disk since it was read (412), or a car started working on the plan (409). */
  get conflict(): boolean {
    return this.status === 412 || this.status === 409;
  }
}

const base = (ordinal: string) => `/api/plans/${encodeURIComponent(ordinal)}/files`;
const urlFor = (ordinal: string, name: string) => `${base(ordinal)}/${encodeURIComponent(name)}`;

async function refusal(method: string, path: string, res: Response): Promise<PlanFileError> {
  const reason = await res
    .json()
    .then((body: { error?: unknown }) => (typeof body.error === "string" ? body.error : null))
    .catch(() => null);
  return new PlanFileError(reason ?? `${method} ${path} answered ${res.status}`, res.status, reason);
}

/** The names the plan holds, in the server's order. An empty array is a plan with no markdown files. */
export async function listPlanFiles(ordinal: string): Promise<string[]> {
  const path = base(ordinal);
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw await refusal("GET", path, res);
  return ((await res.json()) as { files: string[] }).files;
}

/** One file's text and the ETag to send back with a save; quotes included, as the server wrote them. */
export async function readPlanFile(ordinal: string, name: string): Promise<{ body: string; etag: string }> {
  const path = urlFor(ordinal, name);
  const res = await fetch(path, { headers: { Accept: "text/markdown" }, credentials: "same-origin" });
  if (!res.ok) throw await refusal("GET", path, res);
  return { body: await res.text(), etag: res.headers.get("ETag") ?? "" };
}

function put(path: string, body: string, etag: string, csrf: string): Promise<Response> {
  return fetch(path, {
    method: "PUT",
    credentials: "same-origin",
    headers: { "Content-Type": "text/markdown", Accept: "application/json", "If-Match": etag, "X-CSRF-Token": csrf },
    body,
  });
}

/**
 * Saves the whole file. A 403 may be a stale CSRF token (the server restarted), so it fetches a new one and tries once
 * more; a 403 that carries its own reason (a read-only name) is final and is thrown as it stands.
 */
export async function savePlanFile(ordinal: string, name: string, body: string, etag: string, csrf: string): Promise<{ etag: string }> {
  const path = urlFor(ordinal, name);
  let res = await put(path, body, etag, csrf);
  if (res.status === 403) {
    const first = await refusal("PUT", path, res.clone());
    if (first.reason === null) {
      resetSession();
      res = await put(path, body, etag, (await getSession()).csrf);
    }
  }
  if (!res.ok) throw await refusal("PUT", path, res);
  const body2 = await res.json().catch(() => ({}) as { etag?: string });
  return { etag: res.headers.get("ETag") ?? (body2 as { etag?: string }).etag ?? "" };
}
