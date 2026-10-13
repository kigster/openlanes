// This page's own id: the participant the chat between machines knows it as (plan 006). Kept in session storage, so a
// reload is the same page, still in its chat; a new tab, or a closed one, is not (D6).
import { ulid } from "ulid";

const PAGE_KEY = "openlanes-page";
let memory: string | null = null;

export function pageId(): string {
  try {
    const kept = sessionStorage.getItem(PAGE_KEY);
    if (kept) return kept;
    const id = ulid();
    sessionStorage.setItem(PAGE_KEY, id);
    return id;
  } catch {
    // Storage refused: one id for as long as this page lives.
    memory ??= ulid();
    return memory;
  }
}

/** The event stream's URL, carrying the page's id so the server relays its chat. */
export const eventsUrl = (): string => `/api/events?page=${encodeURIComponent(pageId())}`;
