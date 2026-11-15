// A matchMedia the tests can turn: jsdom has none of its own, and the stub in setup.ts never matches anything.
import { vi } from "vitest";

/**
 * Replaces window.matchMedia until `vi.unstubAllGlobals()`.
 *
 * @param matches which queries match, asked again on every read, so a test can change its answer
 * @return `change()`, which tells every listener to read again, as a resize across the line would
 */
export function stubMedia(matches: (query: string) => boolean): { change: () => void } {
  const listeners = new Set<() => void>();
  vi.stubGlobal("matchMedia", (query: string) => ({
    get matches() {
      return matches(query);
    },
    media: query,
    addEventListener: (_: string, fn: () => void) => listeners.add(fn),
    removeEventListener: (_: string, fn: () => void) => listeners.delete(fn),
  }));
  return { change: () => listeners.forEach(fn => fn()) };
}
