// The page's door to the project settings (plan 058). One synchronous PUT: a refused field and a refused guard both
// come back on the request that sent them, as typed errors the form can place.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiError, getSession, resetSession } from "./client";
import type { SettingsDocument, SettingsFieldError, SettingsRefusalKind, SettingsSaveResult, SettingsValues } from "./types";

export const SETTINGS_KEY = ["settings"] as const;

/** 422: `errors` names each refused field by its key path; nothing was written. */
export class SettingsValidationError extends ApiError {
  readonly errors: SettingsFieldError[];
  constructor(errors: SettingsFieldError[]) {
    super("The settings were refused", 422);
    this.name = "SettingsValidationError";
    this.errors = errors;
  }
}

/** 409: a guard refused the save; `refusal` is which one and `reason` is the server's words. Nothing was written. */
export class SettingsRefusalError extends ApiError {
  readonly refusal: SettingsRefusalKind;
  readonly reason: string;
  constructor(refusal: SettingsRefusalKind, reason: string) {
    super(reason, 409);
    this.name = "SettingsRefusalError";
    this.refusal = refusal;
    this.reason = reason;
  }
}

/** GET /api/settings. */
export async function fetchSettings(): Promise<SettingsDocument> {
  const path = "/api/settings";
  const res = await fetch(path, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  if (!res.ok) throw new ApiError(`GET ${path} answered ${res.status}`, res.status);
  return (await res.json()) as SettingsDocument;
}

function put(values: SettingsValues, etag: string, csrf: string): Promise<Response> {
  return fetch("/api/settings", {
    method: "PUT",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json", "If-Match": etag, "X-CSRF-Token": csrf },
    body: JSON.stringify({ values }),
  });
}

/** PUT /api/settings. A 403 may be a stale CSRF token (the server restarted), so it fetches a new one and tries once more. */
export async function saveSettings(values: SettingsValues, etag: string): Promise<SettingsSaveResult> {
  let res = await put(values, etag, (await getSession()).csrf);
  if (res.status === 403) {
    resetSession();
    res = await put(values, etag, (await getSession()).csrf);
  }
  if (res.ok) return (await res.json()) as SettingsSaveResult;
  const body = (await res.json().catch(() => ({}))) as { errors?: SettingsFieldError[]; refusal?: SettingsRefusalKind; reason?: string };
  if (res.status === 422) throw new SettingsValidationError(body.errors ?? []);
  if (res.status === 409 && body.refusal) throw new SettingsRefusalError(body.refusal, body.reason ?? body.refusal);
  throw new ApiError(`PUT /api/settings answered ${res.status}`, res.status);
}

export const useSettings = () => useQuery({ queryKey: SETTINGS_KEY, queryFn: fetchSettings });

/** Saves, then refetches so the page holds the new etag and values. */
export function useSaveSettings() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ values, etag }: { values: SettingsValues; etag: string }) => saveSettings(values, etag),
    onSuccess: () => client.invalidateQueries({ queryKey: SETTINGS_KEY }),
  });
}
