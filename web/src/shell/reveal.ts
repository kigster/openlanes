// A page's nav menu asks for one of the page's panels by id: open it and scroll to it. The page may not be mounted yet
// (a pick from another page), so the id waits here until the page takes it on mount; a page already up hears an event.

/** One page's channel: its menu reveals, its page takes and listens. */
export interface Revealer {
  /** Opens and scrolls to panel `id`, whether or not the page is on screen yet. */
  reveal: (id: string) => void;
  /** The panel a pick asked for before the page mounted, once: taking it clears it. */
  takePending: () => string | null;
  /** Calls `open` for each pick while the page is mounted; returns the unsubscribe. */
  onReveal: (open: (id: string) => void) => () => void;
}

/**
 * @param channel the page's name, so two pages' picks never cross
 * @param scroll scrolls to the panel once it is on the page
 */
export function revealer(channel: string, scroll: (id: string) => void): Revealer {
  const event = `openlanes:reveal:${channel}`;
  let pending: string | null = null;
  return {
    reveal: id => {
      pending = id;
      window.dispatchEvent(new CustomEvent<string>(event, { detail: id }));
      scroll(id);
    },
    takePending: () => {
      const id = pending;
      pending = null;
      return id;
    },
    onReveal: open => {
      const listener = (e: Event) => {
        pending = null;
        open((e as CustomEvent<string>).detail);
      };
      window.addEventListener(event, listener);
      return () => window.removeEventListener(event, listener);
    },
  };
}

/** Scrolls to the element with `elementId` once it is on the page; the page may still be loading, so it waits up to ~2s. */
export function scrollWhenThere(elementId: string, frames = 120): void {
  const el = document.getElementById(elementId);
  if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  else if (frames > 0) requestAnimationFrame(() => scrollWhenThere(elementId, frames - 1));
}
