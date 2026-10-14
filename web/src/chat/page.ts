// This page's own id: the participant the chat between machines knows it as (plan 006). Kept in session storage, so a
// reload is the same page, still in its chat; a new tab, or a closed one, is not (D6).
//
// A duplicated tab, or one opened with an opener, starts with a copy of this tab's session storage, and would take
// the same id: two tabs as one participant, draining one queue between them. So a live page holds its id in memory
// only, takes it out of storage as it starts, and puts it back as it unloads, where only its own reload finds it.
import { ulid } from "ulid";

const PAGE_KEY = "openlanes-page";
let mine: string | null = null;

function keep(id: string): void {
  try {
    sessionStorage.setItem(PAGE_KEY, id);
  } catch {
    // storage refused: the reload is a new page
  }
}

function release(): void {
  try {
    sessionStorage.removeItem(PAGE_KEY);
  } catch {
    // storage refused: nothing kept to copy
  }
}

export function pageId(): string {
  if (mine) return mine;
  let kept: string | null = null;
  try {
    kept = sessionStorage.getItem(PAGE_KEY);
  } catch {
    // Storage refused: one id for as long as this page lives.
  }
  const id = kept || ulid();
  mine = id;
  release();
  window.addEventListener("pagehide", () => keep(id));
  // Back from the back-forward cache: live again, so out of storage again.
  window.addEventListener("pageshow", e => e.persisted && release());
  return id;
}

/** The event stream's URL, carrying the page's id so the server relays its chat. */
export const eventsUrl = (): string => `/api/events?page=${encodeURIComponent(pageId())}`;
