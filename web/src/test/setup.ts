import "@testing-library/jest-dom/vitest";
import { afterEach, expect } from "vitest";
import { cleanup } from "@testing-library/react";
import * as matchers from "vitest-axe/matchers";

expect.extend(matchers);
afterEach(() => cleanup());

// jsdom lacks these; Radix and CodeMirror reach for them.
// React Flow draws an edge only once a node has reported its size through the observer; a Radix or CodeMirror observer
// is left silent, as before, since those only wanted to hear about later resizes.
globalThis.ResizeObserver ??= class {
  readonly cb: (entries: Array<{ target: Element }>) => void;
  constructor(cb: (entries: Array<{ target: Element }>) => void) {
    this.cb = cb;
  }
  observe(target: Element) {
    if (target.classList.contains("react-flow__node")) queueMicrotask(() => this.cb([{ target }]));
  }
  unobserve() {}
  disconnect() {}
} as unknown as typeof ResizeObserver;
// jsdom lays nothing out, so a React Flow node measures as its fixed size here and everything else as 0, as before.
for (const [prop, size] of [["offsetWidth", 220], ["offsetHeight", 72]] as const) {
  const original = Object.getOwnPropertyDescriptor(HTMLElement.prototype, prop)!.get!;
  Object.defineProperty(HTMLElement.prototype, prop, {
    configurable: true,
    get(this: HTMLElement) {
      return this.classList.contains("react-flow__node") ? size : (original.call(this) as number);
    },
  });
}
// user-event dispatches mouse events with no `view`; d3-drag (React Flow's node drag) reads `event.view.document`.
const view = Object.getOwnPropertyDescriptor(UIEvent.prototype, "view")!.get!;
Object.defineProperty(UIEvent.prototype, "view", { configurable: true, get(this: UIEvent) { return (view.call(this) as Window | null) ?? window; } });
window.matchMedia ??= ((query: string) => ({ matches: false, media: query, onchange: null, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {}, dispatchEvent: () => false })) as typeof window.matchMedia;
Element.prototype.scrollIntoView ??= function () {};
Element.prototype.hasPointerCapture ??= () => false;
Element.prototype.releasePointerCapture ??= function () {};
// jsdom has no PointerEvent, so fireEvent.pointer* would build a bare Event without coordinates or a button.
globalThis.PointerEvent ??= class PointerEvent extends MouseEvent {
  readonly pointerId: number;
  constructor(type: string, init: PointerEventInit = {}) {
    super(type, init);
    this.pointerId = init.pointerId ?? 0;
  }
} as unknown as typeof PointerEvent;
// React Flow reads the canvas transform through DOMMatrixReadOnly, which jsdom does not have.
globalThis.DOMMatrixReadOnly ??= class {
  m22 = 1;
} as unknown as typeof DOMMatrixReadOnly;
